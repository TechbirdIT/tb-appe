# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
Default role-targeted mobile dashboard config
=============================================
Seeds ``Mobile App Dashboard`` sections targeted per archetype so a fresh bench
renders a sensible role-tailored home for all 20 SB profiles without any app
release. Config only — the live data each widget shows is resolved by the app
at runtime from the ``data_source`` gateway endpoint carried in each item's
``json``.

Idempotent upsert keyed on ``section_name``:

    bench --site appe.local execute tb_appe.setup.seed_dashboards.execute
    bench --site appe.local execute tb_appe.setup.seed_dashboards.purge

Targeting recap (tb_appe.api.rbac.is_visible): a section is visible if it's
untargeted, ``all_users``, the user's archetype box is ticked, or a role /
role-profile / department match. Archetypes are inclusive by rank here — e.g. a
team section ticks supervisor+manager+executive.
"""

import json

import frappe


def _item(label, action, icon=None, color=None, data_source=None, render=None, extra=None):
    """One Mobile App Dashboard Items row. Behaviour lives in the json blob so
    the client can drive navigation + live data without new schema."""
    blob = {"action": action}
    if icon:
        blob["icon"] = icon
    if color:
        blob["color"] = color
    if data_source:
        blob["data_source"] = f"tb_appe.api.hrms_gateway.{data_source}"
    if render:
        blob["render"] = render
    if extra:
        blob.update(extra)
    return {
        "label": label,
        "type": "Screen",
        "screen_name": action,
        "active": 1,
        "json": json.dumps(blob),
    }


# targeting keys: all_users | show_executive | show_manager | show_supervisor | show_staff
_SECTIONS = [
    {
        "section_name": "Quick Actions",
        "section_view": "Grid View",
        "sequence_id": 10,
        "targeting": {"all_users": 1},
        "items": [
            _item("Check In / Out", "checkin", "log-in", "#0369A1", data_source="checkin_status"),
            _item("Attendance", "attendance", "calendar-check", "#16A34A", data_source="my_attendance"),
            _item("Leave", "leave", "palm-tree", "#F97316", data_source="my_leave_balance"),
            _item("Payslips", "payslips", "banknote", "#1E3A8A", data_source="my_payslips"),
            _item("Expenses", "expenses", "receipt", "#D97706", data_source="my_expenses"),
        ],
    },
    {
        "section_name": "My Leave Balance",
        "section_view": "Number Card View",
        "sequence_id": 20,
        "targeting": {"all_users": 1},
        "items": [
            _item("Leave Balance", "leave", data_source="my_leave_balance", render="leave_rings"),
        ],
    },
    {
        "section_name": "My Team",
        "section_view": "Horizontal Scrollable View",
        "sequence_id": 30,
        "targeting": {"show_supervisor": 1, "show_manager": 1, "show_executive": 1},
        "items": [
            _item("Team", "team", "users", "#1E3A8A", data_source="my_team", render="team_roster"),
        ],
    },
    {
        "section_name": "Pending Approvals",
        "section_view": "List View",
        "sequence_id": 40,
        "targeting": {"show_supervisor": 1, "show_manager": 1, "show_executive": 1},
        "items": [
            _item("Approvals", "approvals", "check-circle", "#DC2626", data_source="team_approvals", render="approvals"),
        ],
    },
    {
        "section_name": "Department Overview",
        "section_view": "Number Card View",
        "sequence_id": 50,
        "targeting": {"show_manager": 1, "show_executive": 1},
        "items": [
            _item("Headcount", "team", "user-check", "#0284C7", data_source="my_team", render="headcount"),
        ],
    },
    {
        "section_name": "Portfolio KPIs",
        "section_view": "Chart View",
        "sequence_id": 60,
        "targeting": {"show_executive": 1},
        "items": [
            _item("Attendance Trend", "analytics", "trending-up", "#1E3A8A", data_source="my_team", render="kpis"),
        ],
    },
]

_SEEDED_NAMES = [s["section_name"] for s in _SECTIONS]

# Pre-existing HR/management sections that shipped untargeted (visible to all).
# We apply sensible targeting ONLY when they're still untargeted, so we never
# clobber a targeting an admin set deliberately.
_LEGACY_TARGETING = {
    "HR Announcements": {"all_users": 1},
    "HR KPIs": {"show_executive": 1, "show_manager": 1, "target_roles": "HR Manager, HR User"},
    "People & Attendance": {"show_executive": 1, "show_manager": 1, "show_supervisor": 1},
    "Recruitment & Growth": {"show_executive": 1, "target_roles": "HR Manager, HR User"},
}


def _is_untargeted(doc) -> bool:
    return not (
        doc.get("all_users")
        or doc.get("show_executive")
        or doc.get("show_manager")
        or doc.get("show_supervisor")
        or doc.get("show_staff")
        or (doc.get("target_role_profiles") or "").strip()
        or (doc.get("target_roles") or "").strip()
        or (doc.get("target_departments") or "").strip()
    )


def _target_legacy():
    changed = []
    for name, tgt in _LEGACY_TARGETING.items():
        doc_name = frappe.db.get_value("Mobile App Dashboard", {"section_name": name})
        if not doc_name:
            continue
        doc = frappe.get_doc("Mobile App Dashboard", doc_name)
        if not _is_untargeted(doc):
            continue  # respect deliberate targeting
        for f in ("all_users", "show_executive", "show_manager", "show_supervisor", "show_staff"):
            doc.set(f, tgt.get(f, 0))
        doc.target_roles = tgt.get("target_roles")
        doc.flags.ignore_permissions = True
        doc.save()
        changed.append(name)
    return changed


def _upsert_section(spec):
    name = frappe.db.get_value("Mobile App Dashboard", {"section_name": spec["section_name"]})
    doc = frappe.get_doc("Mobile App Dashboard", name) if name else frappe.new_doc("Mobile App Dashboard")
    doc.section_name = spec["section_name"]
    doc.status = "Active"
    doc.section_view = spec["section_view"]
    doc.sequence_id = spec["sequence_id"]
    # reset targeting, then apply spec
    for f in ("all_users", "show_executive", "show_manager", "show_supervisor", "show_staff"):
        doc.set(f, spec["targeting"].get(f, 0))
    doc.set("items", [])
    for it in spec["items"]:
        doc.append("items", it)
    doc.flags.ignore_permissions = True
    doc.save() if name else doc.insert(ignore_permissions=True)


def execute():
    for spec in _SECTIONS:
        _upsert_section(spec)
    legacy = _target_legacy()
    frappe.db.commit()
    print(f"Seeded {len(_SECTIONS)} role-targeted dashboard sections: {_SEEDED_NAMES}")
    if legacy:
        print(f"Applied default targeting to untargeted legacy sections: {legacy}")
    return {"seeded": len(_SECTIONS), "legacy_targeted": legacy}


def purge():
    removed = 0
    for name in _SEEDED_NAMES:
        doc = frappe.db.get_value("Mobile App Dashboard", {"section_name": name})
        if doc:
            frappe.delete_doc("Mobile App Dashboard", doc, force=1, ignore_permissions=True)
            removed += 1
    frappe.db.commit()
    print(f"Purged {removed} seeded dashboard sections.")
    return {"purged": removed}
