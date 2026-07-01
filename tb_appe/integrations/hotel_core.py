# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
tb_hotel_core hybrid gateway
============================
tb_appe is the *only* backend the mobile app talks to. When ``tb_hotel_core`` is
installed on the same site (the StayBird deployment), this module lets tb_appe
reuse its mature, scope-checked HRMS surface **in-process** — no HTTP bridge,
because both apps share the site and session.

When ``tb_hotel_core`` is absent, the same public API degrades to a generic
implementation built on the vanilla ``hrms`` / ``erpnext`` apps, so the mobile
app keeps working on a plain bench.

Nothing here is whitelisted. The whitelisted mobile surface lives in
``tb_appe.api.rbac`` and ``tb_appe.api.hrms_gateway`` and calls into here.
"""

import frappe

HOTEL_CORE = "tb_hotel_core"

# Full-access roles never get employee-level scoping (mirrors
# tb_hotel_core.permissions._get_employee_scope so the fallback matches).
_FULL_ACCESS_ROLES = ("System Manager", "HR Manager", "HR User")


def has_hotel_core() -> bool:
    """True when tb_hotel_core is installed on this site (request-cached)."""
    cached = getattr(frappe.local, "_tb_appe_has_hotel_core", None)
    if cached is None:
        cached = HOTEL_CORE in frappe.get_installed_apps()
        frappe.local._tb_appe_has_hotel_core = cached
    return cached


def call(dotted_path: str, *args, **kwargs):
    """Resolve and call a tb_hotel_core function by dotted path.

    Raises RuntimeError if hotel_core isn't installed — callers that offer a
    generic fallback should guard with ``has_hotel_core()`` first.
    """
    if not has_hotel_core():
        raise RuntimeError(f"{HOTEL_CORE} is not installed; cannot call {dotted_path}")
    return frappe.get_attr(dotted_path)(*args, **kwargs)


# ---------------------------------------------------------------------------
# Session employee
# ---------------------------------------------------------------------------
def get_session_employee(throw: bool = False):
    """Employee name linked to the current session user, or None.

    Delegates to tb_hotel_core's resolver when present (keeps company scoping in
    one place); otherwise resolves generically against ERPNext/Appe Employee.
    """
    if has_hotel_core():
        try:
            return call("tb_hotel_core.api.hrms._get_session_employee")
        except frappe.DoesNotExistError:
            if throw:
                raise
            return None

    user = frappe.session.user
    doctype = "Employee" if "erpnext" in frappe.get_installed_apps() else "Appe Employee"
    emp = frappe.db.get_value(doctype, {"user_id": user}, "name")
    if not emp and throw:
        frappe.throw(
            frappe._("No employee record found for your user account"),
            frappe.DoesNotExistError,
        )
    return emp


# ---------------------------------------------------------------------------
# Employee scope (hierarchical RBAC)
# ---------------------------------------------------------------------------
def resolve_employee_scope(user: str | None = None):
    """Employee scope for the user.

    Returns ``None`` for full access, a list of employee names for scoped
    access, or ``[]`` when the user has no linked employee. Delegates to
    tb_hotel_core when present; otherwise reproduces the same self + direct
    reports + department-head + approver logic against ERPNext.
    """
    if has_hotel_core():
        return call("tb_hotel_core.permissions._get_employee_scope", user)
    return _generic_employee_scope(user)


def _generic_employee_scope(user: str | None = None):
    """Fallback scope resolver for benches without tb_hotel_core."""
    user = user or frappe.session.user
    if user == "Administrator":
        return None
    if "erpnext" not in frappe.get_installed_apps():
        return None  # no ERPNext Employee model to scope against

    roles = frappe.get_roles(user)
    if any(r in roles for r in _FULL_ACCESS_ROLES):
        return None

    emp = frappe.db.get_value(
        "Employee",
        {"user_id": user, "status": "Active"},
        ["name", "department", "company", "branch"],
        as_dict=True,
    )
    if not emp:
        return []

    company = emp.company
    scope = {emp.name}

    scope.update(
        frappe.get_all(
            "Employee",
            filters={"reports_to": emp.name, "company": company, "status": "Active"},
            pluck="name",
        )
    )

    if "Department Head" in roles and emp.department:
        dept_filters = {"company": company, "status": "Active"}
        if emp.branch:
            dept_filters["branch"] = emp.branch
        if not (emp.department or "").startswith("Management"):
            dept_filters["department"] = emp.department
        elif not emp.branch:
            dept_filters["department"] = emp.department
        scope.update(frappe.get_all("Employee", filters=dept_filters, pluck="name"))

    if "Leave Approver" in roles:
        scope.update(
            frappe.get_all(
                "Employee",
                filters={"leave_approver": user, "company": company, "status": "Active"},
                pluck="name",
            )
        )
    if "Expense Approver" in roles:
        scope.update(
            frappe.get_all(
                "Employee",
                filters={"expense_approver": user, "company": company, "status": "Active"},
                pluck="name",
            )
        )

    return sorted(scope)
