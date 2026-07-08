# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
Shifts gateway
==============
The ``tb_appe.api.shifts.*`` surface the mobile app calls for shift
scheduling. Reuses HRMS's Shift Assignment / Shift Request doctypes (and
their overlap validation) rather than reinventing them.

Same invariants as hrms_gateway:
  * "my_*" reads are always pinned to the caller's own employee.
  * Manager endpoints never widen access beyond the caller's supervisory
    scope (``hotel_core.resolve_employee_scope``): scope ``None`` = full
    access (HR/admin), a list = exactly those employees, ``[]`` = nothing.

Writes run with ``ignore_permissions`` AFTER an explicit scope check
(``_require_shift_writer``) because scoped managers hold neither HR User nor
HR Manager (granting those would defeat the scope model). Document
validation — including HRMS's OverlappingShiftError / MultipleShiftError —
still runs, and audit fields stay the real caller.
"""

import frappe
from frappe import _

from tb_appe.api.hrms_gateway import _err, _ok, _require_employee, _require_scope_member
from tb_appe.integrations import hotel_core

ASSIGNMENT_FIELDS = [
    "name", "employee", "employee_name", "shift_type", "start_date",
    "end_date", "status", "shift_location", "docstatus",
]

ROSTER_MAX_DAYS = 62


def _time_str(value):
    """Shift time -> string; a midnight timedelta(0) is falsy but real."""
    return "" if value is None else str(value)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _clean_err(e):
    """ValidationError → readable envelope (overlap messages carry HTML)."""
    return _err(frappe.utils.strip_html(str(e) or "Could not save the shift"))


def _getdate(value, label):
    if not value:
        frappe.throw(_("{0} is required").format(label))
    try:
        return frappe.utils.getdate(value)
    except Exception:
        frappe.throw(_("{0} is not a valid date").format(label))


def _shift_type_map(names):
    """Batch Shift Type -> {start_time, end_time, color} for display."""
    names = sorted({n for n in names if n})
    if not names:
        return {}
    rows = frappe.get_all(
        "Shift Type",
        filters={"name": ["in", names]},
        fields=["name", "start_time", "end_time", "color"],
        ignore_permissions=True,
    )
    return {
        r["name"]: {
            "start_time": _time_str(r.get("start_time")),
            "end_time": _time_str(r.get("end_time")),
            "color": r.get("color"),
        }
        for r in rows
    }


def _serialize_assignment(row, type_map):
    t = type_map.get(row.get("shift_type"), {})
    return {
        "name": row.get("name"),
        "employee": row.get("employee"),
        "employee_name": row.get("employee_name"),
        "shift_type": row.get("shift_type"),
        "start_date": str(row.get("start_date") or ""),
        "end_date": str(row.get("end_date") or ""),
        "status": row.get("status"),
        "shift_location": row.get("shift_location"),
        "start_time": t.get("start_time", ""),
        "end_time": t.get("end_time", ""),
        "color": t.get("color"),
    }


def _assignments_in_range(employees, start, end):
    """Submitted Active assignments for `employees` overlapping [start, end].

    An open-ended assignment (end_date NULL) overlaps every future range, so
    the end-date condition must be an OR: end_date >= start OR end_date IS NULL.
    """
    return frappe.get_all(
        "Shift Assignment",
        filters={
            "employee": ["in", employees],
            "docstatus": 1,
            "status": "Active",
            "start_date": ["<=", str(end)],
        },
        or_filters=[
            ["end_date", "is", "not set"],
            ["end_date", ">=", str(start)],
        ],
        fields=ASSIGNMENT_FIELDS,
        order_by="start_date asc",
        ignore_permissions=True,
    )


def _leaves_in_range(employees, start, end):
    return frappe.get_all(
        "Leave Application",
        filters={
            "employee": ["in", employees],
            "status": "Approved",
            "docstatus": 1,
            "from_date": ["<=", str(end)],
            "to_date": [">=", str(start)],
        },
        fields=["name", "employee", "leave_type", "from_date", "to_date", "half_day"],
        ignore_permissions=True,
    )


def _require_shift_writer(employee):
    """Gate for every shift write. The target `employee` must be schedulable
    by the caller:
      * scope None (HR / admin)  -> anyone, including themselves;
      * scope list               -> employee must be IN the scope, must not be
                                    the caller's own record (self-scheduling
                                    goes through the request flow), and the
                                    caller must actually have a team;
      * scope []                 -> nothing.
    """
    scope = hotel_core.resolve_employee_scope()
    if scope is None:
        return
    if not scope or len(scope) < 2:
        frappe.throw(_("You are not permitted to manage shifts"), frappe.PermissionError)
    if employee not in scope:
        frappe.throw(_("This employee is outside your scope"), frappe.PermissionError)
    if employee == hotel_core.get_session_employee():
        frappe.throw(
            _("You cannot assign your own shifts — submit a shift request instead"),
            frappe.PermissionError,
        )


def _can_write_shift(employee):
    try:
        _require_shift_writer(employee)
        return True
    except frappe.PermissionError:
        return False


# ---------------------------------------------------------------------------
# Employee self-service (session-pinned)
# ---------------------------------------------------------------------------
@frappe.whitelist()
def my_shifts(limit=50):
    """The caller's own current + upcoming shift assignments."""
    emp = _require_employee()
    if not emp:
        return _err("No employee record is linked to your user")
    today = frappe.utils.getdate()
    rows = frappe.get_all(
        "Shift Assignment",
        filters={"employee": emp, "docstatus": 1, "status": "Active"},
        or_filters=[
            ["end_date", "is", "not set"],
            ["end_date", ">=", str(today)],
        ],
        fields=ASSIGNMENT_FIELDS,
        order_by="start_date asc",
        limit=frappe.utils.cint(limit) or 50,
        ignore_permissions=True,
    )
    type_map = _shift_type_map([r["shift_type"] for r in rows])
    records = [_serialize_assignment(r, type_map) for r in rows]
    current = [
        r for r in records
        if frappe.utils.getdate(r["start_date"]) <= today
        and (not r["end_date"] or frappe.utils.getdate(r["end_date"]) >= today)
    ]
    upcoming = [r for r in records if frappe.utils.getdate(r["start_date"]) > today]
    return _ok({"current": current, "upcoming": upcoming, "records": records})


@frappe.whitelist()
def my_shift_calendar(start_date, end_date):
    """Shifts + approved leaves + holidays for the caller's own employee over
    a date range (the app renders a week strip from this)."""
    emp = _require_employee()
    if not emp:
        return _err("No employee record is linked to your user")
    start = _getdate(start_date, "start_date")
    end = _getdate(end_date, "end_date")
    if end < start:
        return _err("end_date must be on or after start_date")
    if (end - start).days > ROSTER_MAX_DAYS:
        return _err(f"Date range too large (max {ROSTER_MAX_DAYS} days)")

    rows = _assignments_in_range([emp], start, end)
    type_map = _shift_type_map([r["shift_type"] for r in rows])
    shifts = [_serialize_assignment(r, type_map) for r in rows]
    leaves = [
        {
            "leave_type": l.get("leave_type"),
            "from_date": str(l.get("from_date") or ""),
            "to_date": str(l.get("to_date") or ""),
            "half_day": l.get("half_day"),
        }
        for l in _leaves_in_range([emp], start, end)
    ]

    holidays = []
    try:
        from erpnext.setup.doctype.employee.employee import get_holiday_list_for_employee

        holiday_list = get_holiday_list_for_employee(emp, raise_exception=False)
        if holiday_list:
            holidays = [
                {"date": str(h["holiday_date"]), "description": h.get("description")}
                for h in frappe.get_all(
                    "Holiday",
                    filters={
                        "parent": holiday_list,
                        "holiday_date": ["between", [str(start), str(end)]],
                    },
                    fields=["holiday_date", "description"],
                    order_by="holiday_date asc",
                    ignore_permissions=True,
                )
            ]
    except Exception:
        pass  # holidays are decorative; never fail the calendar over them

    return _ok({"shifts": shifts, "leaves": leaves, "holidays": holidays})


@frappe.whitelist()
def shift_types():
    """Shift Type master list (safe for all authenticated users — needed for
    the request flow and the manager assign sheet)."""
    rows = frappe.get_all(
        "Shift Type",
        fields=["name", "start_time", "end_time", "color"],
        order_by="name asc",
        ignore_permissions=True,
    )
    for r in rows:
        r["start_time"] = _time_str(r.get("start_time"))
        r["end_time"] = _time_str(r.get("end_time"))
    return _ok(rows)


@frappe.whitelist()
def shift_locations():
    """Shift Location master list (empty on HRMS versions without it)."""
    if not frappe.db.exists("DocType", "Shift Location"):
        return _ok([])
    return _ok(
        frappe.get_all(
            "Shift Location",
            fields=["name"],
            order_by="name asc",
            ignore_permissions=True,
        )
    )


@frappe.whitelist()
def my_shift_requests(limit=20):
    """The caller's own shift requests, newest first."""
    emp = _require_employee()
    if not emp:
        return _err("No employee record is linked to your user")
    rows = frappe.get_all(
        "Shift Request",
        filters={"employee": emp, "docstatus": ["!=", 2]},
        fields=["name", "shift_type", "from_date", "to_date", "status", "approver"],
        order_by="creation desc",
        limit=frappe.utils.cint(limit) or 20,
        ignore_permissions=True,
    )
    for r in rows:
        r["from_date"] = str(r.get("from_date") or "")
        r["to_date"] = str(r.get("to_date") or "")
    return _ok(rows)


def _resolve_shift_approver(emp):
    """Shift Request approver for `emp`. HRMS's validate_approver only accepts
    the employee's shift_request_approver or a Department Approver row
    (parentfield shift_request_approver) — anything else is rejected on
    insert, so there is deliberately no reports_to fallback here."""
    doc = frappe.db.get_value(
        "Employee", emp, ["shift_request_approver", "department"], as_dict=True
    )
    if not doc:
        return None
    if doc.shift_request_approver:
        return doc.shift_request_approver
    if doc.department:
        approver = frappe.db.get_value(
            "Department Approver",
            {"parent": doc.department, "parentfield": "shift_request_approver"},
            "approver",
        )
        if approver:
            return approver
    return None


@frappe.whitelist(methods=["POST"])
def request_shift(shift_type, from_date, to_date=None):
    """Self-service shift request (Draft). Lands in the approver's
    pending_approvals inbox and is actioned via approve_shift/reject_shift."""
    emp = _require_employee()
    if not emp:
        return _err("No employee record is linked to your user")
    if not shift_type or not frappe.db.exists("Shift Type", shift_type):
        return _err("Choose a valid shift type")
    start = _getdate(from_date, "from_date")
    end = _getdate(to_date, "to_date") if to_date else None
    if end and end < start:
        return _err("to_date must be on or after from_date")
    approver = _resolve_shift_approver(emp)
    if not approver:
        return _err("No shift approver is configured for you — contact HR")
    try:
        doc = frappe.get_doc(
            {
                "doctype": "Shift Request",
                "employee": emp,
                "shift_type": shift_type,
                "from_date": str(start),
                "to_date": str(end) if end else None,
                "approver": approver,
                "status": "Draft",
                "company": frappe.db.get_value("Employee", emp, "company"),
            }
        )
        doc.insert(ignore_permissions=True)
        frappe.db.commit()
        return _ok({"name": doc.name, "approver": approver})
    except frappe.PermissionError:
        raise
    except frappe.ValidationError as e:
        return _clean_err(e)


# ---------------------------------------------------------------------------
# Manager / HR (scope-verified)
# ---------------------------------------------------------------------------
@frappe.whitelist()
def team_roster(start_date, end_date, employee=None, department=None, limit=200):
    """Shifts + leaves per team member over a date range. Members with no
    shift still appear (the roster must show who is unscheduled)."""
    start = _getdate(start_date, "start_date")
    end = _getdate(end_date, "end_date")
    if end < start:
        return _err("end_date must be on or after start_date")
    if (end - start).days > ROSTER_MAX_DAYS:
        return _err(f"Date range too large (max {ROSTER_MAX_DAYS} days)")

    scope = hotel_core.resolve_employee_scope()
    if isinstance(scope, list) and not scope:
        return _ok({"start_date": str(start), "end_date": str(end), "members": []})

    filters = {"status": "Active"}
    if isinstance(scope, list):
        filters["name"] = ["in", scope]
    if department:
        filters["department"] = department
    if employee:
        _require_scope_member(employee)
        filters["name"] = employee
    members = frappe.get_all(
        "Employee",
        filters=filters,
        fields=["name", "employee_name", "designation", "department", "image"],
        order_by="employee_name asc",
        limit=min(frappe.utils.cint(limit) or 200, 500),
        ignore_permissions=True,
    )
    if not members:
        return _ok({"start_date": str(start), "end_date": str(end), "members": []})

    emp_ids = [m["name"] for m in members]
    rows = _assignments_in_range(emp_ids, start, end)
    type_map = _shift_type_map([r["shift_type"] for r in rows])
    shifts_by_emp = {}
    for r in rows:
        shifts_by_emp.setdefault(r["employee"], []).append(_serialize_assignment(r, type_map))
    leaves_by_emp = {}
    for l in _leaves_in_range(emp_ids, start, end):
        leaves_by_emp.setdefault(l["employee"], []).append(
            {
                "leave_type": l.get("leave_type"),
                "from_date": str(l.get("from_date") or ""),
                "to_date": str(l.get("to_date") or ""),
                "half_day": l.get("half_day"),
            }
        )

    my_emp = hotel_core.get_session_employee()
    out = []
    for m in members:
        out.append(
            {
                "employee": m["name"],
                "employee_name": m.get("employee_name"),
                "designation": m.get("designation"),
                "department": m.get("department"),
                "image": m.get("image"),
                "shifts": shifts_by_emp.get(m["name"], []),
                "leaves": leaves_by_emp.get(m["name"], []),
                "can_edit": scope is None or (m["name"] in (scope or []) and m["name"] != my_emp),
            }
        )
    return _ok({"start_date": str(start), "end_date": str(end), "members": out})


@frappe.whitelist()
def shift_detail(name):
    """One assignment, with shift-type times and whether the caller may edit."""
    row = frappe.db.get_value("Shift Assignment", name, ASSIGNMENT_FIELDS, as_dict=True)
    if not row:
        return _err("Shift assignment not found")
    if row.employee != _require_employee():
        _require_scope_member(row.employee)
    data = _serialize_assignment(row, _shift_type_map([row.shift_type]))
    data["can_edit"] = _can_write_shift(row.employee)
    return _ok(data)


def _insert_assignment(employee, shift_type, start_date, end_date, status, shift_location):
    """Build + submit a Shift Assignment. Company always comes from the
    Employee record, never the client. HRMS validation (incl. overlap
    checks) runs on insert/submit."""
    doc = frappe.get_doc(
        {
            "doctype": "Shift Assignment",
            "employee": employee,
            "company": frappe.db.get_value("Employee", employee, "company"),
            "shift_type": shift_type,
            "start_date": str(start_date),
            "end_date": str(end_date) if end_date else None,
            "status": status or "Active",
            "shift_location": shift_location or None,
        }
    )
    doc.insert(ignore_permissions=True)
    doc.flags.ignore_permissions = True
    doc.submit()
    return doc


@frappe.whitelist(methods=["POST"])
def assign_shift(employee, shift_type, start_date, end_date=None, status="Active", shift_location=None):
    """Create a submitted Shift Assignment for a scoped report (or anyone,
    for HR/admin)."""
    _require_shift_writer(employee)
    if frappe.db.get_value("Employee", employee, "status") != "Active":
        return _err("This employee is not active")
    if not shift_type or not frappe.db.exists("Shift Type", shift_type):
        return _err("Choose a valid shift type")
    start = _getdate(start_date, "start_date")
    end = _getdate(end_date, "end_date") if end_date else None
    if end and end < start:
        return _err("end_date must be on or after start_date")
    if status not in ("Active", "Inactive"):
        return _err("Invalid status")
    try:
        doc = _insert_assignment(employee, shift_type, start, end, status, shift_location)
        frappe.db.commit()
        return _ok({"name": doc.name})
    except frappe.PermissionError:
        raise
    except frappe.ValidationError as e:
        return _clean_err(e)


@frappe.whitelist(methods=["POST"])
def update_shift(name, shift_type=None, start_date=None, end_date=None, status=None, shift_location=None, clear_end_date=0):
    """Replace an assignment: cancel the submitted doc and create a new one
    with the merged values (only end_date/status are allow_on_submit, so
    in-place edits can't change the shift or dates). Atomic — a validation
    failure rolls the cancel back too. Pass clear_end_date=1 to make the
    replacement open-ended (an empty end_date just keeps the old one)."""
    doc = frappe.get_doc("Shift Assignment", name)
    _require_shift_writer(doc.employee)
    new_shift_type = shift_type or doc.shift_type
    if not frappe.db.exists("Shift Type", new_shift_type):
        return _err("Choose a valid shift type")
    new_start = _getdate(start_date, "start_date") if start_date else doc.start_date
    if frappe.utils.cint(clear_end_date):
        new_end = None
    else:
        new_end = _getdate(end_date, "end_date") if end_date else doc.end_date
    if new_end and frappe.utils.getdate(new_end) < frappe.utils.getdate(new_start):
        return _err("end_date must be on or after start_date")
    new_status = status or doc.status
    if new_status not in ("Active", "Inactive"):
        return _err("Invalid status")
    try:
        if doc.docstatus == 1:
            doc.flags.ignore_permissions = True
            doc.cancel()
        replacement = _insert_assignment(
            doc.employee, new_shift_type, new_start, new_end, new_status,
            shift_location if shift_location is not None else doc.shift_location,
        )
        frappe.db.commit()
        return _ok({"name": replacement.name, "replaced": name})
    except frappe.PermissionError:
        raise
    except frappe.ValidationError as e:
        frappe.db.rollback()
        return _clean_err(e)


@frappe.whitelist(methods=["POST"])
def end_shift(name, end_date):
    """Close an assignment on a date (end_date is allow_on_submit, so this is
    a plain save on the submitted doc — same mechanism as HRMS's roster)."""
    doc = frappe.get_doc("Shift Assignment", name)
    _require_shift_writer(doc.employee)
    end = _getdate(end_date, "end_date")
    if end < frappe.utils.getdate(doc.start_date):
        return _err("end_date must be on or after the shift's start date")
    try:
        doc.end_date = str(end)
        doc.flags.ignore_permissions = True
        doc.save()
        frappe.db.commit()
        return _ok({"name": doc.name, "end_date": str(end)})
    except frappe.PermissionError:
        raise
    except frappe.ValidationError as e:
        return _clean_err(e)


@frappe.whitelist(methods=["POST"])
def delete_shift(name):
    """Remove an assignment entirely (cancel + delete for submitted docs)."""
    doc = frappe.get_doc("Shift Assignment", name)
    _require_shift_writer(doc.employee)
    try:
        if doc.docstatus == 1:
            doc.flags.ignore_permissions = True
            doc.cancel()
        frappe.delete_doc("Shift Assignment", name, ignore_permissions=True)
        frappe.db.commit()
        return _ok({"deleted": name})
    except frappe.PermissionError:
        raise
    except frappe.ValidationError as e:
        frappe.db.rollback()
        return _clean_err(e)
