# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
Local RBAC demo seed (DEV ONLY)
===============================
Creates one demo User + linked Employee for each of the 20 StayBird ("SB") role
profiles, wired into a small org hierarchy so the mobile RBAC dashboards and the
hierarchical employee-scope can be exercised end to end on a local bench.

Idempotent: re-running skips anything that already exists. Everything it creates
uses the ``@sb.appe.local`` email domain so ``purge()`` can cleanly remove it.

    bench --site appe.local execute tb_appe.setup.seed_rbac_demo.execute
    bench --site appe.local execute tb_appe.setup.seed_rbac_demo.purge

NEVER run on production. It fabricates users with a shared known password.
"""

import frappe
from frappe.utils import getdate

DOMAIN = "sb.appe.local"
DEMO_PASSWORD = "Appe@12345"

# Hotel departments to ensure under the site's company (name -> is reused if the
# "<Name> - <abbr>" record already exists, e.g. the ERPNext defaults).
_DEPARTMENTS = [
    "Front Office",
    "Housekeeping",
    "Food & Beverage",
    "Kitchen",
    "Banquets",
    "Maintenance",
    "Security",
    "Management",
    "Human Resources",
    "Accounts",
    "Sales",
]

_BRANCHES = ["Capital", "Icon Cluster"]

# profile -> (department, branch, reports_to_profile | None, designation)
_ROSTER = {
    "SB General Manager": ("Management", "Capital", None, "General Manager"),
    "SB Property Manager": ("Management", "Icon Cluster", "SB General Manager", "Property Manager"),
    "SB Revenue Manager": ("Sales", "Capital", "SB General Manager", "Revenue Manager"),
    "SB Front Office Manager": ("Front Office", "Capital", "SB General Manager", "Front Office Manager"),
    "SB F&B Manager": ("Food & Beverage", "Capital", "SB General Manager", "F&B Manager"),
    "SB Kitchen Manager": ("Kitchen", "Capital", "SB F&B Manager", "Kitchen Manager"),
    "SB Banquet Manager": ("Banquets", "Capital", "SB General Manager", "Banquet Manager"),
    "SB Accounts Manager": ("Accounts", "Capital", "SB General Manager", "Accounts Manager"),
    "SB HR Manager": ("Human Resources", "Capital", "SB General Manager", "HR Manager"),
    "SB Sales Manager": ("Sales", "Capital", "SB Revenue Manager", "Sales Manager"),
    "SB Housekeeping Supervisor": ("Housekeeping", "Capital", "SB General Manager", "Housekeeping Supervisor"),
    "SB Front Office Executive": ("Front Office", "Capital", "SB Front Office Manager", "Front Office Executive"),
    "SB Room Attendant": ("Housekeeping", "Capital", "SB Housekeeping Supervisor", "Room Attendant"),
    "SB F&B Service": ("Food & Beverage", "Capital", "SB F&B Manager", "F&B Steward"),
    "SB Kitchen": ("Kitchen", "Capital", "SB Kitchen Manager", "Commis Chef"),
    "SB Banquet Coordinator": ("Banquets", "Capital", "SB Banquet Manager", "Banquet Coordinator"),
    "SB Accountant": ("Accounts", "Capital", "SB Accounts Manager", "Accountant"),
    "SB HR Executive": ("Human Resources", "Capital", "SB HR Manager", "HR Executive"),
    "SB Maintenance": ("Maintenance", "Capital", "SB General Manager", "Maintenance Technician"),
    "SB Security": ("Security", "Capital", "SB General Manager", "Security Guard"),
}


def _abbr(company):
    return frappe.get_cached_value("Company", company, "abbr")


def _slug(profile):
    return (
        profile.replace("SB ", "")
        .replace("&", "and")
        .replace(" ", ".")
        .lower()
    )


def _ensure_departments(company):
    abbr = _abbr(company)
    for dept in _DEPARTMENTS:
        name = f"{dept} - {abbr}"
        if not frappe.db.exists("Department", name):
            frappe.get_doc(
                {
                    "doctype": "Department",
                    "department_name": dept,
                    "company": company,
                    "is_group": 0,
                }
            ).insert(ignore_permissions=True)


def _ensure_branches():
    for br in _BRANCHES:
        if not frappe.db.exists("Branch", br):
            frappe.get_doc({"doctype": "Branch", "branch": br}).insert(ignore_permissions=True)


def _ensure_designations():
    for _profile, (_dept, _branch, _reports, designation) in _ROSTER.items():
        if not frappe.db.exists("Designation", designation):
            frappe.get_doc(
                {"doctype": "Designation", "designation_name": designation}
            ).insert(ignore_permissions=True)


def _profile_roles(profile):
    return frappe.get_all(
        "Has Role", filters={"parent": profile, "parenttype": "Role Profile"}, pluck="role"
    )


def _ensure_user(profile, full_name):
    email = f"{_slug(profile)}@{DOMAIN}"
    if not frappe.db.exists("User", email):
        user = frappe.get_doc(
            {
                "doctype": "User",
                "email": email,
                "first_name": full_name,
                "send_welcome_email": 0,
                "new_password": DEMO_PASSWORD,
            }
        )
        user.append("role_profiles", {"role_profile": profile})
        user.flags.ignore_permissions = True
        user.insert()
    else:
        user = frappe.get_doc("User", email)
        assigned = [r.role_profile for r in (user.role_profiles or [])]
        if profile not in assigned:
            user.append("role_profiles", {"role_profile": profile})
            user.save(ignore_permissions=True)

    # Belt-and-suspenders: apply the profile's bundled roles explicitly, so this
    # doesn't depend on the User controller's role-profile propagation.
    roles = _profile_roles(profile)
    if roles:
        frappe.get_doc("User", email).add_roles(*roles)
    return email


def _ensure_employee(profile, full_name, email, company, dept_abbr):
    dept, branch, _reports, designation = _ROSTER[profile]
    existing = frappe.db.get_value("Employee", {"user_id": email}, "name")
    if existing:
        return existing
    emp = frappe.get_doc(
        {
            "doctype": "Employee",
            "employee_name": full_name,
            "first_name": full_name,
            "user_id": email,
            "company": company,
            "status": "Active",
            "gender": "Other",
            "date_of_birth": getdate("1990-01-01"),
            "date_of_joining": getdate("2024-01-01"),
            "department": f"{dept} - {dept_abbr}",
            "branch": branch,
            "designation": designation,
            "company_email": email,
        }
    )
    emp.flags.ignore_permissions = True
    emp.insert()
    return emp.name


def execute():
    """Idempotently seed the 20-profile RBAC demo org."""
    company = frappe.defaults.get_global_default("company") or frappe.db.get_value("Company", {}, "name")
    if not company:
        frappe.throw("No Company found on this site.")
    abbr = _abbr(company)

    _ensure_departments(company)
    _ensure_branches()
    _ensure_designations()

    # Pass 1: users + employees (no reports_to yet).
    profile_to_emp = {}
    for profile, (dept, branch, _reports, designation) in _ROSTER.items():
        full_name = profile.replace("SB ", "")
        email = _ensure_user(profile, full_name)
        emp_name = _ensure_employee(profile, full_name, email, company, abbr)
        profile_to_emp[profile] = emp_name

    # Pass 2: wire reports_to now that every employee exists.
    for profile, (_dept, _branch, reports_to_profile, _desig) in _ROSTER.items():
        if not reports_to_profile:
            continue
        emp = profile_to_emp.get(profile)
        mgr = profile_to_emp.get(reports_to_profile)
        if emp and mgr and frappe.db.get_value("Employee", emp, "reports_to") != mgr:
            frappe.db.set_value("Employee", emp, "reports_to", mgr)

    # ERPNext auto-creates an "Employee = self" User Permission when user_id is
    # set, which hard-restricts even managers/HR to their own record across all
    # doctypes. tb_hotel_core scopes Employee via its permission-query instead,
    # so strip these auto UPs and let that be the single source of truth.
    stripped = _strip_employee_user_permissions(profile_to_emp)

    frappe.db.commit()
    print(f"Seeded {len(profile_to_emp)} SB demo users/employees on '{company}'.")
    print(f"Stripped {stripped} auto Employee User Permissions.")
    print(f"Login domain: @{DOMAIN}  password: {DEMO_PASSWORD}")
    return {"seeded": len(profile_to_emp), "company": company, "stripped_up": stripped}


def _strip_employee_user_permissions(profile_to_emp):
    removed = 0
    for profile in profile_to_emp:
        email = f"{_slug(profile)}@{DOMAIN}"
        for up in frappe.get_all(
            "User Permission", filters={"user": email, "allow": "Employee"}, pluck="name"
        ):
            frappe.delete_doc("User Permission", up, ignore_permissions=True)
            removed += 1
    return removed


def purge():
    """Remove all @sb.appe.local demo users + their employees."""
    emails = frappe.get_all(
        "User", filters={"email": ["like", f"%@{DOMAIN}"]}, pluck="name"
    )
    removed = 0
    for email in emails:
        for emp in frappe.get_all("Employee", filters={"user_id": email}, pluck="name"):
            # detach reports_to pointers first to avoid link errors
            for child in frappe.get_all("Employee", filters={"reports_to": emp}, pluck="name"):
                frappe.db.set_value("Employee", child, "reports_to", None)
            frappe.delete_doc("Employee", emp, force=1, ignore_permissions=True)
        frappe.delete_doc("User", email, force=1, ignore_permissions=True)
        removed += 1
    frappe.db.commit()
    print(f"Purged {removed} demo users and their employees.")
    return {"purged": removed}
