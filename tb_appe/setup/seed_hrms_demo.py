# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
Local HRMS sample data (DEV ONLY)
=================================
Populates realistic HRMS data for the 20 ``@sb.appe.local`` demo employees so
the mobile self-service + approvals screens show real content: leave
allocations & balances, attendance history, today's check-ins, a couple of
pending leave/expense approvals per manager, and monthly payslips.

Idempotent-ish: guarded per section, skips employees that already have the row.
Everything is scoped to the demo employees; NEVER run on production.

    bench --site appe.local execute tb_appe.setup.seed_hrms_demo.execute
    bench --site appe.local execute tb_appe.setup.seed_hrms_demo.purge
"""

from datetime import timedelta

import frappe
from frappe.utils import add_days, getdate, nowdate

DOMAIN = "sb.appe.local"
COMPANY = "TechbirdIT"
HOLIDAY_LIST = "SB Demo Holidays"
SALARY_STRUCTURE = "SB Demo Salary"
YEAR_START = "2026-01-01"
YEAR_END = "2026-12-31"

# Leave type -> annual allocation
_LEAVE_ALLOC = {"Privilege Leave": 18, "Casual Leave": 12, "Sick Leave": 12}

# base monthly salary by rank keyword (matched against employee_name)
_BASE_BY_KEYWORD = [
    ("General Manager", 180000),
    ("Property Manager", 150000),
    ("Manager", 95000),
    ("Supervisor", 60000),
    ("Executive", 48000),
    ("Coordinator", 42000),
    ("Accountant", 55000),
    ("Revenue", 120000),
]
_BASE_DEFAULT = 32000


def _demo_employees():
    return frappe.get_all(
        "Employee",
        filters={"company_email": ["like", f"%@{DOMAIN}"]},
        fields=["name", "employee_name", "user_id", "reports_to", "department"],
    )


def _base_for(name):
    for kw, amt in _BASE_BY_KEYWORD:
        if kw.lower() in name.lower():
            return amt
    return _BASE_DEFAULT


# ---------------------------------------------------------------------------
def ensure_holiday_list():
    if frappe.db.exists("Holiday List", HOLIDAY_LIST):
        return
    hl = frappe.new_doc("Holiday List")
    hl.holiday_list_name = HOLIDAY_LIST
    hl.from_date = getdate(YEAR_START)
    hl.to_date = getdate(YEAR_END)
    hl.weekly_off = "Sunday"
    hl.flags.ignore_permissions = True
    hl.insert()
    hl.get_weekly_off_dates()
    hl.save()
    frappe.db.set_value("Company", COMPANY, "default_holiday_list", HOLIDAY_LIST)
    frappe.db.commit()


def ensure_holiday_assignment():
    """HRMS resolves an employee's holidays via a submitted Holiday List
    Assignment (it ignores Employee.holiday_list / Company default). One
    company-level assignment covers every employee."""
    if frappe.db.exists(
        "Holiday List Assignment",
        {"applicable_for": "Company", "assigned_to": COMPANY, "docstatus": 1},
    ):
        return
    doc = frappe.get_doc(
        {
            "doctype": "Holiday List Assignment",
            "applicable_for": "Company",
            "assigned_to": COMPANY,
            "employee_company": COMPANY,
            "holiday_list": HOLIDAY_LIST,
            "from_date": getdate(YEAR_START),
        }
    )
    doc.flags.ignore_permissions = True
    doc.insert()
    doc.submit()
    frappe.db.commit()


def seed_leave_allocations(emps):
    made = 0
    for e in emps:
        frappe.db.set_value("Employee", e.name, "holiday_list", HOLIDAY_LIST)
        for ltype, qty in _LEAVE_ALLOC.items():
            exists = frappe.db.exists(
                "Leave Allocation",
                {
                    "employee": e.name,
                    "leave_type": ltype,
                    "from_date": YEAR_START,
                    "docstatus": 1,
                },
            )
            if exists:
                continue
            doc = frappe.new_doc("Leave Allocation")
            doc.employee = e.name
            doc.leave_type = ltype
            doc.from_date = getdate(YEAR_START)
            doc.to_date = getdate(YEAR_END)
            doc.new_leaves_allocated = qty
            doc.flags.ignore_permissions = True
            doc.insert()
            doc.submit()
            made += 1
    return made


def seed_attendance(emps, days=30):
    made = 0
    today = getdate(nowdate())
    for e in emps:
        for i in range(days):
            d = add_days(today, -i)
            if getdate(d).weekday() == 6:  # Sunday off
                continue
            if frappe.db.exists("Attendance", {"employee": e.name, "attendance_date": d}):
                continue
            # deterministic variety without RNG (blocked in this env)
            slot = (e.name.__hash__() + i) % 12
            status = "On Leave" if slot == 3 else ("Absent" if slot == 7 else "Present")
            doc = frappe.new_doc("Attendance")
            doc.employee = e.name
            doc.attendance_date = d
            doc.status = status
            doc.company = COMPANY
            if status == "Present":
                doc.working_hours = 8 + (i % 2)
            doc.flags.ignore_permissions = True
            try:
                doc.insert()
                doc.submit()
                made += 1
            except Exception:
                frappe.db.rollback()
    return made


def seed_checkins(emps):
    made = 0
    now = frappe.utils.now_datetime()
    for idx, e in enumerate(emps):
        if idx % 3 == 2:  # ~2/3 punched in today
            continue
        start = f"{nowdate()} 00:00:00"
        end = f"{nowdate()} 23:59:59"
        if frappe.db.exists(
            "Employee Checkin", {"employee": e.name, "time": ["between", [start, end]]}
        ):
            continue
        doc = frappe.new_doc("Employee Checkin")
        doc.employee = e.name
        doc.log_type = "IN"
        doc.time = now
        doc.flags.ignore_permissions = True
        try:
            doc.insert()
            made += 1
        except Exception:
            frappe.db.rollback()
    return made


def seed_leave_requests(emps):
    """A pending (Open) leave application from each employee that has a manager,
    so the manager's approvals inbox is populated."""
    made = 0
    by_name = {e.name: e for e in emps}
    today = getdate(nowdate())
    for e in emps:
        if not e.reports_to or e.reports_to not in by_name:
            continue
        approver_user = frappe.db.get_value("Employee", e.reports_to, "user_id")
        if not approver_user:
            continue
        frm = add_days(today, 7 + (len(e.name) % 5))
        to = add_days(frm, 1)
        if frappe.db.exists(
            "Leave Application",
            {"employee": e.name, "from_date": frm, "docstatus": 0},
        ):
            continue
        doc = frappe.new_doc("Leave Application")
        doc.employee = e.name
        doc.leave_type = "Casual Leave"
        doc.from_date = frm
        doc.to_date = to
        doc.leave_approver = approver_user
        doc.description = "Personal work (demo)"
        doc.status = "Open"
        doc.flags.ignore_permissions = True
        try:
            doc.insert()
            made += 1
        except Exception:
            frappe.db.rollback()
    return made


def _expense_account():
    for kw in ("Administrative Expenses", "Indirect Expenses", "Expenses"):
        a = frappe.db.get_value(
            "Account",
            {"company": COMPANY, "root_type": "Expense", "is_group": 0,
             "account_name": ["like", f"%{kw}%"]},
            "name",
        )
        if a:
            return a
    return frappe.db.get_value(
        "Account", {"company": COMPANY, "root_type": "Expense", "is_group": 0}, "name"
    )


def ensure_expense_types():
    acct = _expense_account()
    for t in ("Travel", "Food", "Supplies"):
        if not frappe.db.exists("Expense Claim Type", t):
            frappe.get_doc(
                {"doctype": "Expense Claim Type", "expense_type": t}
            ).insert(ignore_permissions=True)
        # Expense Claim validation needs a per-company default account.
        if acct:
            doc = frappe.get_doc("Expense Claim Type", t)
            if not any((r.company == COMPANY) for r in doc.accounts):
                doc.append("accounts", {"company": COMPANY, "default_account": acct})
                doc.flags.ignore_permissions = True
                doc.save()


def seed_expense_claims(emps):
    made = 0
    by_name = {e.name: e for e in emps}
    today = getdate(nowdate())
    etype = "Travel" if frappe.db.exists("Expense Claim Type", "Travel") else None
    if not etype:
        return 0
    for e in emps[:8]:  # a handful is enough
        approver_user = (
            frappe.db.get_value("Employee", e.reports_to, "user_id")
            if e.reports_to in by_name
            else None
        )
        if frappe.db.exists(
            "Expense Claim", {"employee": e.name, "docstatus": 0}
        ):
            continue
        doc = frappe.new_doc("Expense Claim")
        doc.employee = e.name
        doc.posting_date = today
        doc.company = COMPANY
        doc.approval_status = "Draft"
        doc.currency = frappe.db.get_value("Company", COMPANY, "default_currency")
        doc.exchange_rate = 1
        if approver_user:
            doc.expense_approver = approver_user
        doc.append(
            "expenses",
            {
                "expense_date": today,
                "expense_type": etype,
                "description": "Client visit cab (demo)",
                "amount": 1200 + (len(e.name) % 5) * 300,
                "sanctioned_amount": 1200 + (len(e.name) % 5) * 300,
            },
        )
        doc.flags.ignore_permissions = True
        try:
            doc.insert()
            frappe.db.commit()
            made += 1
        except Exception:
            frappe.db.rollback()
    return made


def ensure_salary_structure():
    if frappe.db.exists("Salary Structure", SALARY_STRUCTURE):
        return frappe.db.get_value(
            "Salary Structure", SALARY_STRUCTURE, "docstatus"
        )
    doc = frappe.get_doc(
        {
            "doctype": "Salary Structure",
            "__newname": SALARY_STRUCTURE,
            "salary_structure_name": SALARY_STRUCTURE,
            "company": COMPANY,
            "payroll_frequency": "Monthly",
            "earnings": [
                {
                    "salary_component": "Basic",
                    "amount_based_on_formula": 1,
                    "formula": "base",
                }
            ],
            "deductions": [
                {
                    "salary_component": "Income Tax",
                    "amount_based_on_formula": 1,
                    "formula": "base * 0.10",
                }
            ],
        }
    )
    doc.flags.ignore_permissions = True
    doc.insert()
    doc.submit()


def seed_salary(emps):
    ensure_salary_structure()
    made = 0
    for e in emps:
        base = _base_for(e.employee_name)
        # Salary Structure Assignment
        if not frappe.db.exists(
            "Salary Structure Assignment",
            {"employee": e.name, "salary_structure": SALARY_STRUCTURE, "docstatus": 1},
        ):
            ssa = frappe.get_doc(
                {
                    "doctype": "Salary Structure Assignment",
                    "employee": e.name,
                    "salary_structure": SALARY_STRUCTURE,
                    "from_date": "2025-07-01",
                    "base": base,
                    "company": COMPANY,
                }
            )
            ssa.flags.ignore_permissions = True
            try:
                ssa.insert()
                ssa.submit()
                frappe.db.commit()
            except Exception:
                frappe.db.rollback()
                continue
        # A payslip for last month
        start, end = "2026-06-01", "2026-06-30"
        if frappe.db.exists(
            "Salary Slip",
            {"employee": e.name, "start_date": start, "docstatus": ["!=", 2]},
        ):
            continue
        slip = frappe.get_doc(
            {
                "doctype": "Salary Slip",
                "employee": e.name,
                "company": COMPANY,
                "start_date": start,
                "end_date": end,
                "posting_date": end,
            }
        )
        slip.flags.ignore_permissions = True
        try:
            slip.insert()
            slip.submit()
            frappe.db.commit()
            made += 1
        except Exception:
            frappe.db.rollback()
    return made


def ensure_shift_types():
    for nm, start, end in [
        ("Morning", "08:00:00", "16:00:00"),
        ("Evening", "16:00:00", "00:00:00"),
        ("General", "09:30:00", "18:30:00"),
    ]:
        if not frappe.db.exists("Shift Type", nm):
            frappe.get_doc(
                {"doctype": "Shift Type", "__newname": nm, "start_time": start, "end_time": end}
            ).insert(ignore_permissions=True)
    frappe.db.commit()


def _approver_for(e, by):
    """Approval routing (airtight, no self-approval):
      * top-level (GM, no reports_to)     -> Administrator
      * HR head (user has HR Manager role) -> Administrator  (HR can't approve HR)
      * everyone else                     -> their reports_to manager's user
    """
    is_top = not e.get("reports_to")
    is_hr_head = bool(e.get("user_id")) and "HR Manager" in frappe.get_roles(e.user_id)
    if is_top or is_hr_head:
        return "Administrator"
    mgr = by.get(e.get("reports_to"))
    return (mgr.get("user_id") if mgr else None) or "Administrator"


def setup_approver_hierarchy():
    """Set Employee leave/expense approvers, grant approver roles, and re-point
    existing pending requests. Also ensures the top of the org (GM) has a leave
    pending Admin approval so the rule is demonstrable."""
    emps = frappe.get_all(
        "Employee",
        filters={"company_email": ["like", f"%@{DOMAIN}"]},
        fields=["name", "employee_name", "user_id", "reports_to", "department"],
    )
    by = {e.name: e for e in emps}

    approver_users = set()
    for e in emps:
        appr = _approver_for(e, by)
        frappe.db.set_value(
            "Employee", e.name, {"leave_approver": appr, "expense_approver": appr}
        )
        approver_users.add(appr)

    # Every approver must hold the approver roles (managers had Leave Approver but
    # not always Expense Approver). Administrator already has both.
    for u in approver_users:
        if u and u != "Administrator" and frappe.db.exists("User", u):
            frappe.get_doc("User", u).add_roles("Leave Approver", "Expense Approver")

    # Re-point existing pending requests to each employee's approver.
    for la in frappe.get_all(
        "Leave Application", filters={"status": "Open", "docstatus": 0}, fields=["name", "employee"]
    ):
        e = by.get(la.employee)
        if e:
            frappe.db.set_value("Leave Application", la.name, "leave_approver", _approver_for(e, by))
    for ec in frappe.get_all(
        "Expense Claim", filters={"approval_status": "Draft", "docstatus": 0}, fields=["name", "employee"]
    ):
        e = by.get(ec.employee)
        if e:
            frappe.db.set_value("Expense Claim", ec.name, "expense_approver", _approver_for(e, by))

    # Ensure the GM (top) has a leave pending Admin approval (they have no
    # reports_to, so the generic request seeder skips them).
    gm = next((e for e in emps if not e.get("reports_to")), None)
    if gm and not frappe.db.exists(
        "Leave Application", {"employee": gm.name, "status": "Open", "docstatus": 0}
    ):
        try:
            doc = frappe.get_doc({
                "doctype": "Leave Application", "employee": gm.name,
                "leave_type": "Casual Leave",
                "from_date": add_days(getdate(nowdate()), 10),
                "to_date": add_days(getdate(nowdate()), 11),
                "leave_approver": "Administrator", "status": "Open",
                "description": "GM leave (demo) — routes to Admin",
            })
            doc.flags.ignore_permissions = True
            doc.insert()
        except Exception:
            frappe.db.rollback()

    frappe.db.commit()
    return len(emps)


def execute():
    emps = _demo_employees()
    if not emps:
        print("No @sb.appe.local demo employees found. Run seed_rbac_demo first.")
        return

    ensure_holiday_list()
    ensure_holiday_assignment()
    ensure_shift_types()
    results = {}
    for label, fn in [
        ("leave_allocations", lambda: seed_leave_allocations(emps)),
        ("attendance", lambda: seed_attendance(emps)),
        ("checkins", lambda: seed_checkins(emps)),
        ("leave_requests", lambda: seed_leave_requests(emps)),
        ("expense_claims", lambda: (ensure_expense_types(), seed_expense_claims(emps))[1]),
        ("payslips", lambda: seed_salary(emps)),
        ("approver_hierarchy", setup_approver_hierarchy),
    ]:
        try:
            results[label] = fn()
            frappe.db.commit()
        except Exception as exc:
            frappe.db.rollback()
            results[label] = f"ERROR: {exc}"
    print("HRMS demo seed:", results)
    return results


def purge():
    emps = [e.name for e in _demo_employees()]
    if not emps:
        print("No demo employees.")
        return
    counts = {}
    for dt in [
        "Salary Slip",
        "Salary Structure Assignment",
        "Attendance",
        "Employee Checkin",
        "Leave Application",
        "Leave Allocation",
        "Expense Claim",
    ]:
        rows = frappe.get_all(dt, filters={"employee": ["in", emps]}, pluck="name")
        for n in rows:
            try:
                doc = frappe.get_doc(dt, n)
                if doc.docstatus == 1:
                    doc.cancel()
                frappe.delete_doc(dt, n, force=1, ignore_permissions=True)
            except Exception:
                frappe.db.rollback()
        counts[dt] = len(rows)
    frappe.db.commit()
    print("Purged:", counts)
    return counts
