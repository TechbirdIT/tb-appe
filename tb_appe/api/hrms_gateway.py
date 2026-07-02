# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
Mobile HRMS gateway
===================
The stable ``tb_appe.api.hrms_gateway.*`` surface the mobile app calls for all
HRMS features. Each endpoint delegates to tb_hotel_core's scope-checked
implementation when it's installed, and falls back to a generic
ERPNext/HRMS implementation otherwise (see ``integrations.hotel_core``).

Two invariants:
  * "my_*" reads are always pinned to the caller's own employee, so the app
    can't over-fetch even if it passes a different employee id.
  * Team / approval endpoints rely on the same hierarchical scope the desk
    enforces — they never widen access.
"""

import json

import frappe
from frappe import _

from tb_appe.integrations import hotel_core

HC = "tb_hotel_core.api.hrms."
HC_MOBILE = "tb_hotel_core.api.mobile_hrms."


def _ok(data=None, **extra):
    out = {"status": True, "data": data}
    out.update(extra)
    return out


def _err(message):
    return {"status": False, "message": str(message)}


def _require_employee():
    """Session employee name, or None (callers return a clean error)."""
    return hotel_core.get_session_employee()


def _self_leave_balance(employee):
    """Leave balance for the caller's OWN employee, computed self-safely.

    tb_hotel_core's get_leave_balance is manager-oriented and requires Leave
    Allocation read permission, which plain self-service staff don't hold. Since
    ``employee`` here is always the session employee (resolved server-side, not
    client-supplied), reading it with ignore_permissions leaks nothing.
    """
    today = frappe.utils.today()
    allocations = frappe.get_all(
        "Leave Allocation",
        filters={
            "employee": employee,
            "from_date": ["<=", today],
            "to_date": [">=", today],
            "docstatus": 1,
        },
        fields=["leave_type", "total_leaves_allocated", "carry_forwarded_leaves_count", "from_date", "to_date"],
        ignore_permissions=True,
    )
    result = []
    for a in allocations:
        allocated = frappe.utils.flt(a.get("total_leaves_allocated") or 0)
        taken = frappe.utils.flt(
            frappe.db.sql(
                """SELECT COALESCE(SUM(total_leave_days), 0) FROM `tabLeave Application`
                   WHERE employee=%s AND leave_type=%s AND status='Approved' AND docstatus=1
                     AND from_date>=%s AND to_date<=%s""",
                (employee, a["leave_type"], str(a["from_date"]), str(a["to_date"])),
            )[0][0]
        )
        result.append(
            {
                "leave_type": a["leave_type"],
                "allocated": allocated,
                "taken": taken,
                "carry_forwarded": frappe.utils.flt(a.get("carry_forwarded_leaves_count") or 0),
                "balance": allocated - taken,
            }
        )
    return result


# ---------------------------------------------------------------------------
# Check-in / check-out
# ---------------------------------------------------------------------------
@frappe.whitelist()
def checkin_status():
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC_MOBILE + "get_checkin_status"))
    # Fallback: reuse tb_appe's own lightweight status.
    from tb_appe.appe_api import employee_checkin_status

    return _ok(employee_checkin_status())


@frappe.whitelist()
def checkin(log_type=None, latitude=None, longitude=None, accuracy=None, selfie=None, property=None):
    if hotel_core.has_hotel_core():
        return _ok(
            hotel_core.call(
                HC_MOBILE + "mobile_checkin",
                log_type=log_type,
                latitude=latitude,
                longitude=longitude,
                accuracy=accuracy,
                selfie=selfie,
                property=property,
            )
        )
    from tb_appe.appe_api import employee_checkin

    return _ok(employee_checkin())


# ---------------------------------------------------------------------------
# Self-service reads (always scoped to the caller)
# ---------------------------------------------------------------------------
@frappe.whitelist()
def my_dashboard():
    """Consolidated self-service home for the logged-in employee."""
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "get_my_dashboard"))
    return _err("Consolidated dashboard requires tb_hotel_core")


# NOTE: the "my_*" reads deliberately query the caller's OWN employee directly
# with ignore_permissions rather than delegating to tb_hotel_core's
# manager-oriented endpoints. Those endpoints gate on desk read-permission for
# Leave Allocation / Salary Slip / Attendance, which plain self-service staff
# ("Employee Self Service") don't hold — so delegation 403s for line staff.
# The employee here is always resolved from the session (never client-supplied),
# so a self-scoped read leaks nothing.
@frappe.whitelist()
def my_leave_balance():
    emp = _require_employee()
    if not emp:
        return _err("No employee record found for your user account")
    return _ok(_self_leave_balance(emp))


@frappe.whitelist()
def leave_types():
    if hotel_core.has_hotel_core():
        try:
            return _ok(hotel_core.call(HC + "get_leave_types"))
        except Exception:
            pass
    return _ok(frappe.get_all("Leave Type", pluck="name"))


@frappe.whitelist()
def my_leaves(status=None, limit=100):
    emp = _require_employee()
    if not emp:
        return _err("No employee record found for your user account")
    filters = {"employee": emp, "docstatus": ["!=", 2]}
    if status:
        filters["status"] = status
    return _ok(
        frappe.get_all(
            "Leave Application",
            filters=filters,
            fields=["name", "leave_type", "from_date", "to_date", "total_leave_days", "status"],
            order_by="from_date desc",
            limit=limit,
            ignore_permissions=True,
        )
    )


@frappe.whitelist()
def my_payslips(limit=24):
    emp = _require_employee()
    if not emp:
        return _err("No employee record found for your user account")
    return _ok(
        frappe.get_all(
            "Salary Slip",
            filters={"employee": emp, "docstatus": 1},
            fields=["name", "start_date", "end_date", "gross_pay", "net_pay", "total_deduction"],
            order_by="start_date desc",
            limit=limit,
            ignore_permissions=True,
        )
    )


@frappe.whitelist()
def payslip_detail(salary_slip_name):
    emp = _require_employee()
    slip_emp = frappe.db.get_value("Salary Slip", salary_slip_name, "employee")
    if not emp or slip_emp != emp:
        return _err("Not permitted")
    return _ok(frappe.get_doc("Salary Slip", salary_slip_name).as_dict())


@frappe.whitelist()
def my_expenses(status=None, limit=50):
    emp = _require_employee()
    if not emp:
        return _err("No employee record found for your user account")
    return _ok(
        frappe.get_all(
            "Expense Claim",
            filters={"employee": emp, "docstatus": ["!=", 2]},
            fields=["name", "posting_date", "total_claimed_amount", "total_sanctioned_amount", "approval_status"],
            order_by="posting_date desc",
            limit=limit,
            ignore_permissions=True,
        )
    )


@frappe.whitelist()
def expense_types():
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "get_expense_claim_types"))
    return _ok(frappe.get_all("Expense Claim Type", pluck="name"))


@frappe.whitelist()
def my_attendance(limit=45):
    """Rolling attendance history for the caller (self-scoped, most recent
    first) — richer than a single calendar month for a mobile history view."""
    emp = _require_employee()
    if not emp:
        return _err("No employee record found for your user account")
    rows = frappe.get_all(
        "Attendance",
        filters={"employee": emp, "docstatus": ["<", 2]},
        fields=["name", "attendance_date", "status", "working_hours"],
        order_by="attendance_date desc",
        limit=limit,
        ignore_permissions=True,
    )
    summary = {"present": 0, "absent": 0, "on_leave": 0}
    for r in rows:
        s = (r.get("status") or "").lower()
        if s == "present":
            summary["present"] += 1
        elif s == "absent":
            summary["absent"] += 1
        elif s in ("on leave", "half day"):
            summary["on_leave"] += 1
    return _ok({"records": rows, **summary})


# ---------------------------------------------------------------------------
# Self-service writes
# ---------------------------------------------------------------------------
@frappe.whitelist()
def apply_leave(leave_type, from_date, to_date, reason=None):
    emp = _require_employee()
    if not emp:
        return _err("No employee record found for your user account")
    if hotel_core.has_hotel_core():
        return _ok(
            hotel_core.call(
                HC + "create_leave_application",
                employee=emp,
                leave_type=leave_type,
                from_date=from_date,
                to_date=to_date,
                reason=reason,
            )
        )
    doc = frappe.get_doc(
        {
            "doctype": "Leave Application",
            "employee": emp,
            "leave_type": leave_type,
            "from_date": from_date,
            "to_date": to_date,
            "description": reason,
            "status": "Open",
        }
    ).insert()
    return _ok({"name": doc.name})


@frappe.whitelist()
def create_expense(posting_date, expenses, expense_approver=None, remark=None):
    emp = _require_employee()
    if not emp:
        return _err("No employee record found for your user account")
    if isinstance(expenses, str):
        expenses = json.loads(expenses)
    if hotel_core.has_hotel_core():
        return _ok(
            hotel_core.call(
                HC + "create_expense_claim",
                employee=emp,
                posting_date=posting_date,
                expenses=expenses,
                expense_approver=expense_approver,
                remark=remark,
            )
        )
    return _err("Expense claim creation requires tb_hotel_core on this bench")


# ---------------------------------------------------------------------------
# Supervisor: team + approvals
# ---------------------------------------------------------------------------
@frappe.whitelist()
def my_team():
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC_MOBILE + "get_my_team"))
    return _err("Team view requires tb_hotel_core on this bench")


@frappe.whitelist()
def team_approvals():
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC_MOBILE + "get_team_pending_approvals"))
    return _err("Approvals require tb_hotel_core on this bench")


def _meta_has(doctype, field):
    return frappe.db.exists("DocType", doctype) and frappe.get_meta(doctype).has_field(field)


def _my_pending_approvals(user=None):
    """Hybrid approval model. A request appears in my inbox when:
      * I'm its DESIGNATED approver (line manager of the employee), OR
      * I have OVERRIDE authority (HR / Admin) — HR/Admin can action ANY request
        in scope. Override never includes my OWN request, and non-admin override
        (HR/GM) never includes requests reserved to the Admin (i.e. the GM's and
        HR head's own, whose approver is Administrator).
    Covers leave, expense, shift and attendance requests."""
    user = user or frappe.session.user
    roles = set(frappe.get_roles(user))
    is_admin = "System Manager" in roles or user == "Administrator"
    is_override = is_admin or bool(roles & {"HR Manager", "HR User"})
    my_emp = hotel_core.get_session_employee()
    scope = hotel_core.resolve_employee_scope(user)

    def _fetch(doctype, base, approver_field, fields, order_by):
        f = dict(base)
        if not is_override:
            f[approver_field] = user
            return frappe.get_all(doctype, filters=f, fields=fields, order_by=order_by, ignore_permissions=True)
        # Override: everything in scope, then drop own + (for HR/GM) admin-reserved.
        if isinstance(scope, list):
            f["employee"] = ["in", scope]
        rows = frappe.get_all(doctype, filters=f, fields=fields, order_by=order_by, ignore_permissions=True)
        if my_emp:
            rows = [r for r in rows if r.get("employee") != my_emp]
        if not is_admin:
            rows = [r for r in rows if r.get(approver_field) != "Administrator"]
        return rows

    out = {"leaves": [], "expenses": [], "shift_requests": [], "attendance_requests": []}
    out["leaves"] = _fetch(
        "Leave Application", {"status": "Open", "docstatus": 0}, "leave_approver",
        ["name", "employee", "employee_name", "leave_type", "from_date", "to_date",
         "total_leave_days", "description", "posting_date", "leave_approver"],
        "from_date asc",
    )
    out["expenses"] = _fetch(
        "Expense Claim", {"approval_status": "Draft", "docstatus": 0}, "expense_approver",
        ["name", "employee", "employee_name", "posting_date", "total_claimed_amount",
         "total_sanctioned_amount", "expense_approver"],
        "posting_date asc",
    )
    if _meta_has("Shift Request", "approver"):
        out["shift_requests"] = frappe.get_all(
            "Shift Request",
            filters={"docstatus": 0, "approver": user, "status": ["!=", "Approved"]},
            fields=["name", "employee", "employee_name", "shift_type", "from_date", "to_date"],
            ignore_permissions=True,
        )
    if _meta_has("Attendance Request", "approver"):
        out["attendance_requests"] = frappe.get_all(
            "Attendance Request",
            filters={"docstatus": 0, "approver": user},
            fields=["name", "employee", "employee_name", "from_date", "to_date", "reason"],
            ignore_permissions=True,
        )
    out["count"] = sum(len(v) for v in out.values() if isinstance(v, list))
    return out


@frappe.whitelist()
def pending_approvals():
    return _ok(_my_pending_approvals())


@frappe.whitelist()
def all_pending():
    """Read-only oversight of ALL pending leave/expense in the caller's scope
    (HR/full-access → org-wide) — matches the org KPI counts. Each row carries
    the assigned approver so HR can see who is actioning it. Distinct from
    `pending_approvals` (only what *I* must approve)."""
    scope = hotel_core.resolve_employee_scope()
    if isinstance(scope, list) and not scope:
        return _ok({"leaves": [], "expenses": []})
    lf = {"status": "Open", "docstatus": 0}
    ef = {"approval_status": "Draft", "docstatus": 0}
    if isinstance(scope, list):
        lf["employee"] = ["in", scope]
        ef["employee"] = ["in", scope]
    leaves = frappe.get_all(
        "Leave Application", filters=lf,
        fields=["name", "employee_name", "leave_type", "from_date", "to_date",
                "total_leave_days", "leave_approver"],
        order_by="from_date asc", ignore_permissions=True,
    )
    expenses = frappe.get_all(
        "Expense Claim", filters=ef,
        fields=["name", "employee_name", "posting_date", "total_claimed_amount",
                "expense_approver"],
        order_by="posting_date asc", ignore_permissions=True,
    )
    return _ok({"leaves": leaves, "expenses": expenses})


# ---------------------------------------------------------------------------
# Company announcements (Appe Post) — gated to admin / management
# ---------------------------------------------------------------------------
@frappe.whitelist(methods=["POST"])
def announce(title, content):
    """Post a Company Announcement (Appe Post). Restricted to admin / GM / HR /
    department managers (rbac._ANNOUNCE_ROLES) — unlike the legacy
    create_appe_post, this is permission-gated."""
    from tb_appe.api.rbac import _ANNOUNCE_ROLES

    if not (set(frappe.get_roles()) & _ANNOUNCE_ROLES):
        frappe.throw(_("You are not permitted to post announcements"), frappe.PermissionError)
    if not (title and str(title).strip() and content and str(content).strip()):
        return _err("Title and content are required")
    title = str(title).strip()
    content = str(content).strip()
    doc = frappe.get_doc({
        "doctype": "Appe Post",
        "title": title,
        "content": content,
        "post": 1,
    })
    doc.insert(ignore_permissions=True)
    frappe.db.commit()

    pushed = _push_announcement(title, content)
    return _ok({"name": doc.name, "pushed": pushed})


def _push_announcement(title, content):
    """Best-effort native push for a new announcement, to every active
    employee, via the existing Mobile App Notification → OneSignal path. Never
    fails the announcement itself (push is a bonus and may be unconfigured)."""
    if not frappe.db.get_single_value("Appe Settings", "onesignal_app_id"):
        return False  # push not configured yet
    try:
        users = frappe.get_all(
            "Employee",
            filters={"status": "Active"},
            pluck="user_id",
            ignore_permissions=True,
        )
        users = sorted({u for u in users if u})
        if not users:
            return False
        note = frappe.new_doc("Mobile App Notification")
        note.title = f"\U0001F4E2 {title}"  # 📢
        note.message = content[:240]
        note.data = frappe.as_json({"type": "announcement"})
        for u in users:
            note.append("users", {"user": u})
        note.flags.ignore_permissions = True
        note.insert()
        note.submit()  # before_submit fires the OneSignal push
        frappe.db.commit()
        return True
    except Exception:
        frappe.db.rollback()
        frappe.log_error("Announcement push failed", "tb_appe.announce")
        return False


@frappe.whitelist()
def directory(search=None, department=None, limit=500):
    """Every employee the caller may SEE (their scope) — distinct from `my_team`
    (direct reports). HR / full-access sees all; a manager sees their scoped set.
    Tap-through detail stays scope-checked via member_detail."""
    scope = hotel_core.resolve_employee_scope()
    if isinstance(scope, list) and not scope:
        return _ok({"count": 0, "employees": []})
    filters = {"status": "Active"}
    if isinstance(scope, list):
        filters["name"] = ["in", scope]
    if department:
        filters["department"] = department
    or_filters = None
    if search:
        or_filters = [
            ["employee_name", "like", f"%{search}%"],
            ["name", "like", f"%{search}%"],
        ]
    rows = frappe.get_all(
        "Employee",
        filters=filters,
        or_filters=or_filters,
        fields=["name", "employee_name", "designation", "department", "branch",
                "image", "cell_number"],
        order_by="employee_name asc",
        limit=limit,
        ignore_permissions=True,
    )
    return _ok({"count": len(rows), "employees": rows})


@frappe.whitelist()
def approve_leave(leave_application_name):
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "approve_leave", leave_application_name=leave_application_name))
    return _err("Approvals require tb_hotel_core on this bench")


@frappe.whitelist()
def reject_leave(leave_application_name, reason=None):
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "reject_leave", leave_application_name=leave_application_name, reason=reason))
    return _err("Approvals require tb_hotel_core on this bench")


@frappe.whitelist()
def approve_expense(expense_claim_name):
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "approve_expense_claim", expense_claim_name=expense_claim_name))
    return _err("Approvals require tb_hotel_core on this bench")


@frappe.whitelist()
def reject_expense(expense_claim_name, reason=None):
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "reject_expense_claim", expense_claim_name=expense_claim_name, reason=reason))
    return _err("Approvals require tb_hotel_core on this bench")


@frappe.whitelist()
def approve_shift(shift_request_name):
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "approve_shift_request", shift_request_name=shift_request_name))
    return _err("Approvals require tb_hotel_core on this bench")


@frappe.whitelist()
def reject_shift(shift_request_name, reason=None):
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "reject_shift_request", shift_request_name=shift_request_name, reason=reason))
    return _err("Approvals require tb_hotel_core on this bench")


@frappe.whitelist()
def approve_attendance(request_name):
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "approve_attendance_request", request_name=request_name))
    return _err("Approvals require tb_hotel_core on this bench")


@frappe.whitelist()
def reject_attendance(request_name):
    if hotel_core.has_hotel_core():
        return _ok(hotel_core.call(HC + "reject_attendance_request", request_name=request_name))
    return _err("Approvals require tb_hotel_core on this bench")


# ---------------------------------------------------------------------------
# Manager analytics + team-member drill-down (scope-checked)
# ---------------------------------------------------------------------------
def _require_scope_member(employee):
    """Reject access unless `employee` is within the caller's supervisory scope
    (None = full access). Mirrors the desk-side employee-scope contract."""
    scope = hotel_core.resolve_employee_scope()
    if scope is not None and employee not in scope:
        frappe.throw(_("Not authorized to view this employee"), frappe.PermissionError)


@frappe.whitelist()
def team_stats():
    """Aggregate KPIs for the caller's team — team size, who's in/present/on
    leave today, and pending approval counts."""
    if not hotel_core.has_hotel_core():
        return _err("Team stats require tb_hotel_core on this bench")
    team = hotel_core.call(HC_MOBILE + "get_my_team")
    members = team.get("team", []) if isinstance(team, dict) else []
    # Pending counts are approver-based (what *I* must action), so they match
    # the approvals inbox rather than the whole team's requests.
    pend = _my_pending_approvals()

    def _status(m):
        return (m.get("attendance_status") or "").lower()

    return _ok(
        {
            "team_size": len(members),
            "present_today": sum(1 for m in members if _status(m) == "present"),
            "on_leave_today": sum(1 for m in members if _status(m) in ("on leave", "half day")),
            "punched_in": sum(1 for m in members if m.get("punched_in")),
            "pending_leaves": len(pend["leaves"]),
            "pending_expenses": len(pend["expenses"]),
            "pending_total": pend["count"],
        }
    )


@frappe.whitelist()
def member_detail(employee):
    """Profile + leave balance + recent attendance + pending leaves for one
    team member. Scope-checked: the caller must supervise this employee."""
    if not employee:
        return _err("employee is required")
    _require_scope_member(employee)

    profile = frappe.db.get_value(
        "Employee",
        employee,
        ["name", "employee_name", "designation", "department", "branch",
         "image", "company_email", "cell_number"],
        as_dict=True,
    )
    attendance = frappe.get_all(
        "Attendance",
        filters={"employee": employee, "docstatus": ["<", 2]},
        fields=["attendance_date", "status", "working_hours"],
        order_by="attendance_date desc",
        limit=30,
        ignore_permissions=True,
    )
    pending_leaves = frappe.get_all(
        "Leave Application",
        filters={"employee": employee, "status": "Open", "docstatus": 0},
        fields=["name", "leave_type", "from_date", "to_date", "total_leave_days"],
        order_by="from_date asc",
        ignore_permissions=True,
    )
    return _ok(
        {
            "employee": profile,
            "leave_balance": _self_leave_balance(employee),
            "attendance": attendance,
            "pending_leaves": pending_leaves,
        }
    )


def _haversine_km(a, b):
    from math import asin, cos, radians, sin, sqrt

    r = 6371.0
    dlat = radians(b["lat"] - a["lat"])
    dlon = radians(b["lng"] - a["lng"])
    h = sin(dlat / 2) ** 2 + cos(radians(a["lat"])) * cos(radians(b["lat"])) * sin(dlon / 2) ** 2
    return 2 * r * asin(sqrt(h))


@frappe.whitelist()
def employee_route(employee=None, date=None):
    """Location trail for a day, built from raw Employee Location points (no
    dependency on the aggregated route summary).

    Location history is a management oversight function: it's viewed by an
    employee's manager, never by the employee about themselves. So `employee`
    is required, self-view is refused, and viewing anyone else is scope-checked
    (the caller must supervise them; HR/Admin have full scope)."""
    if not employee:
        return _err("An employee must be specified")
    me = _require_employee()
    if me and employee == me:
        frappe.throw(
            _("Location history is viewed by your manager, not about yourself"),
            frappe.PermissionError,
        )
    _require_scope_member(employee)
    emp = employee

    day = date or frappe.utils.today()
    rows = frappe.get_all(
        "Employee Location",
        filters={"employee": emp, "timestamp": ["between", [f"{day} 00:00:00", f"{day} 23:59:59"]]},
        fields=["latitude", "longitude", "timestamp"],
        order_by="timestamp asc",
        ignore_permissions=True,
    )
    pts = [
        {"lat": frappe.utils.flt(r.latitude), "lng": frappe.utils.flt(r.longitude), "time": str(r.timestamp)}
        for r in rows
        if r.latitude and r.longitude
    ]
    dist = sum(_haversine_km(pts[i - 1], pts[i]) for i in range(1, len(pts)))
    emp_row = frappe.db.get_value("Employee", emp, ["employee_name", "designation"], as_dict=True) or {}

    # Reverse-geocode just the start + end (cached; OSM/Nominatim) so the map
    # can label where the day began and ended without geocoding every point.
    start_address = end_address = None
    if pts:
        from tb_appe.api.geocode import reverse_geocode

        start_address = reverse_geocode(pts[0]["lat"], pts[0]["lng"])
        if len(pts) > 1:
            end_address = reverse_geocode(pts[-1]["lat"], pts[-1]["lng"])
        pts[0]["address"] = start_address
        if len(pts) > 1:
            pts[-1]["address"] = end_address

    return _ok(
        {
            "employee": emp,
            "employee_name": emp_row.get("employee_name"),
            "date": str(day),
            "points": pts,
            "count": len(pts),
            "distance_km": round(dist, 2),
            "start_address": start_address,
            "end_address": end_address,
        }
    )
