# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
RBAC bootstrap for the mobile app
=================================
``get_me`` is the single call the app makes right after ``login_user``. It
returns everything the client needs to render a role-tailored home: the user's
roles, role profiles, linked-employee summary, hierarchical-scope shape, a
coarse *archetype* (executive / manager / supervisor / staff), and a set of
capability booleans that gate which sections and actions the app shows.

The archetype + capabilities are intentionally derived server-side so the app
never has to hard-code role logic — Phase 2's config-driven dashboards target
role profiles / roles / departments directly, and the app just renders what the
server returns.
"""

import re

import frappe

from tb_appe.integrations import hotel_core

# The 20 "SB" role profiles collapse into four rendered dashboard archetypes.
# Kept explicit (not heuristic) so every StayBird profile maps predictably.
_PROFILE_ARCHETYPE = {
    # Executive — cross-department overview
    "SB General Manager": "executive",
    "SB Property Manager": "executive",
    "SB Revenue Manager": "executive",
    # Department manager — own team + approvals + dept metrics
    "SB Front Office Manager": "manager",
    "SB F&B Manager": "manager",
    "SB Kitchen Manager": "manager",
    "SB Banquet Manager": "manager",
    "SB Accounts Manager": "manager",
    "SB HR Manager": "manager",
    "SB Sales Manager": "manager",
    # Supervisor — direct reports board + own HRMS
    "SB Housekeeping Supervisor": "supervisor",
    # Line staff — self-service only
    "SB Front Office Executive": "staff",
    "SB Room Attendant": "staff",
    "SB F&B Service": "staff",
    "SB Kitchen": "staff",
    "SB Banquet Coordinator": "staff",
    "SB Accountant": "staff",
    "SB HR Executive": "staff",
    "SB Maintenance": "staff",
    "SB Security": "staff",
}

# Fallback ranking when a user has no SB profile — highest match wins.
_EXECUTIVE_ROLES = ("Hotel Manager", "GM", "Revenue Manager")
_MANAGER_ROLES = ("HR Manager", "Accounts Manager", "Sales Manager", "Department Head")
_SUPERVISOR_ROLES = ("Housekeeping Supervisor",)


def get_user_role_profiles(user: str) -> list[str]:
    """Role profiles assigned to a user (v15 child table + legacy single field)."""
    profiles = set()
    # Legacy single field
    single = frappe.db.get_value("User", user, "role_profile_name")
    if single:
        profiles.add(single)
    # v15+ multi role-profile child table
    try:
        profiles.update(
            frappe.get_all(
                "Has Role Profile",
                filters={"parent": user, "parenttype": "User"},
                pluck="role_profile",
            )
        )
    except Exception:
        pass
    return sorted(p for p in profiles if p)


def _archetype(roles: list[str], role_profiles: list[str], scope) -> str:
    """Coarse dashboard archetype for the user."""
    for p in role_profiles:
        if p in _PROFILE_ARCHETYPE:
            return _PROFILE_ARCHETYPE[p]

    # No known SB profile — fall back to roles.
    if any(r in roles for r in _EXECUTIVE_ROLES) or scope is None:
        # scope is None => full/HR access; treat as executive-level overview.
        if any(r in roles for r in _EXECUTIVE_ROLES):
            return "executive"
    if any(r in roles for r in _MANAGER_ROLES):
        return "manager"
    if any(r in roles for r in _SUPERVISOR_ROLES):
        return "supervisor"
    # A plain employee whose only report is themselves is staff; anyone who
    # supervises others but matched nothing above is a supervisor.
    if isinstance(scope, list) and len(scope) > 1:
        return "supervisor"
    return "staff"


def _capabilities(roles: list[str], scope) -> dict:
    """Feature gates the app uses to show/hide sections and actions."""
    has_team = scope is None or (isinstance(scope, list) and len(scope) > 1)
    return {
        "is_hr": any(r in roles for r in ("HR Manager", "HR User")),
        "is_admin": "System Manager" in roles or frappe.session.user == "Administrator",
        "can_approve_leave": "Leave Approver" in roles or "HR Manager" in roles,
        "can_approve_expense": "Expense Approver" in roles or "HR Manager" in roles,
        "has_team": has_team,
        "can_view_payroll": any(
            r in roles for r in ("HR Manager", "HR User", "Accounts Manager", "Accounts User")
        ),
        # Who may post Company Announcements — admin, GM/property management, HR,
        # and department managers / other administerial positions.
        "can_announce": bool(set(roles) & _ANNOUNCE_ROLES),
        "self_service": True,
    }


# Administerial / managerial roles allowed to post Company Announcements.
_ANNOUNCE_ROLES = {
    "System Manager",       # Administrator
    "Administrator",
    "GM",
    "Hotel Manager",        # GM / Property Manager
    "HR Manager",
    "HR User",
    "Department Head",      # department managers + supervisors
    "Accounts Manager",
    "Sales Manager",
    "Revenue Manager",
}


def build_context(user: str | None = None) -> dict:
    """Resolve the RBAC context for the session user.

    Shared by ``get_me`` and the config-driven dashboard resolver so archetype /
    scope logic lives in exactly one place.
    """
    user = user or frappe.session.user
    roles = frappe.get_roles(user)
    role_profiles = get_user_role_profiles(user)

    employee = hotel_core.get_session_employee()
    emp = None
    if employee:
        emp = frappe.db.get_value(
            "Employee",
            employee,
            [
                "name",
                "employee_name",
                "designation",
                "department",
                "branch",
                "company",
                "image",
                "reports_to",
                "date_of_joining",
                "company_email",
                "cell_number",
            ],
            as_dict=True,
        )

    scope = hotel_core.resolve_employee_scope(user)
    return {
        "user": user,
        "roles": roles,
        "role_profiles": role_profiles,
        "employee": emp,
        "department": emp.department if emp else None,
        "scope": scope,
        "archetype": _archetype(roles, role_profiles, scope),
        "capabilities": _capabilities(roles, scope),
    }


def _split(text: str | None) -> list[str]:
    """Split a comma/newline separated targeting field into clean tokens."""
    return [t.strip() for t in re.split(r"[,\n]", text or "") if t.strip()]


def is_visible(row, ctx: dict) -> bool:
    """Whether a targeted dashboard/module row is visible to the context user.

    ``row`` is any object exposing the targeting fields (``all_users``,
    ``show_executive/manager/supervisor/staff``, ``target_role_profiles``,
    ``target_roles``, ``target_departments``). A row with NO targeting set is
    visible to everyone (backward compatible with pre-RBAC config).
    """
    get = row.get if isinstance(row, dict) else lambda k: getattr(row, k, None)

    archetype_checks = {
        "executive": get("show_executive"),
        "manager": get("show_manager"),
        "supervisor": get("show_supervisor"),
        "staff": get("show_staff"),
    }
    profiles = _split(get("target_role_profiles"))
    roles_t = _split(get("target_roles"))
    depts = _split(get("target_departments"))

    has_targeting = bool(
        get("all_users") or any(archetype_checks.values()) or profiles or roles_t or depts
    )
    if not has_targeting:
        return True
    if get("all_users"):
        return True
    if archetype_checks.get(ctx["archetype"]):
        return True
    if set(profiles) & set(ctx["role_profiles"]):
        return True
    if set(roles_t) & set(ctx["roles"]):
        return True
    if ctx.get("department") and ctx["department"] in depts:
        return True
    return False


@frappe.whitelist()
def get_me():
    """Role-aware bootstrap for the mobile client."""
    ctx = build_context()
    scope = ctx["scope"]
    scope_shape = {
        "full_access": scope is None,
        "count": None if scope is None else len(scope),
        "is_supervisor": scope is None or (isinstance(scope, list) and len(scope) > 1),
    }

    userdata = frappe.db.get_value(
        "User",
        ctx["user"],
        ["name", "email", "full_name", "username", "user_image", "mobile_no", "time_zone"],
        as_dict=True,
    )

    return {
        "status": True,
        "data": {
            "user": userdata,
            "roles": ctx["roles"],
            "role_profiles": ctx["role_profiles"],
            "employee": ctx["employee"],
            "scope": scope_shape,
            "archetype": ctx["archetype"],
            "capabilities": ctx["capabilities"],
            "hotel_core": hotel_core.has_hotel_core(),
            # Live-location tracking is an org policy (Appe Settings), NOT an
            # employee toggle — the app only asks the employee to grant the OS
            # permission when this is on.
            "location_tracking": _location_tracking_enabled(),
            # Public OneSignal App ID so the client can initialise push (the
            # REST key stays server-side). Empty when push isn't configured.
            "onesignal_app_id": frappe.db.get_single_value("Appe Settings", "onesignal_app_id") or "",
        },
    }


def _location_tracking_enabled() -> bool:
    try:
        return bool(frappe.db.get_single_value("Appe Settings", "enable_live_location_tracking"))
    except Exception:
        return False
