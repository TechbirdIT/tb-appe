# Copyright (c) 2026, TechbirdIT and contributors
# Admin configuration for the check-in Wi-Fi geofence.
#
# Company access points (BSSIDs) live in the `allowed_wifi` child table of the
# `Appe Settings` single. Only admins may read/write them; every user then
# receives their company's list via `rbac.get_me` (`wifi_check_in`), and the
# check-in endpoint enforces it server-side.

import json

import frappe

from tb_appe.api.rbac import allowed_wifi_bssids


def _require_admin():
    roles = frappe.get_roles(frappe.session.user)
    if "System Manager" not in roles and frappe.session.user != "Administrator":
        frappe.throw("You are not permitted to configure company Wi-Fi.", frappe.PermissionError)


def _user_company() -> str | None:
    return frappe.db.get_value("Employee", {"user_id": frappe.session.user}, "company")


@frappe.whitelist()
def get_company_wifi():
    """Admin: the company's allowed access points."""
    _require_admin()
    company = _user_company()
    rows = frappe.get_all(
        "Appe Wifi Network",
        filters={"parenttype": "Appe Settings"},
        fields=["company", "ssid", "bssid"],
        order_by="idx asc",
    )
    networks = [
        {"ssid": r.get("ssid") or "", "bssid": (r.get("bssid") or "")}
        for r in rows
        if (not r.get("company") or not company or r.get("company") == company)
    ]
    return {"status": True, "data": {"company": company, "networks": networks}}


@frappe.whitelist()
def set_company_wifi(networks):
    """Admin: replace the company's allowed access points.

    ``networks`` is a JSON array of ``{"ssid", "bssid"}``. Rows belonging to
    other companies are preserved.
    """
    _require_admin()
    if isinstance(networks, str):
        networks = json.loads(networks or "[]")
    company = _user_company()

    settings = frappe.get_single("Appe Settings")
    # Preserve other companies' rows; drop this company's (and global) rows.
    kept = [
        {"company": r.company, "ssid": r.ssid, "bssid": r.bssid}
        for r in settings.allowed_wifi
        if r.company and company and r.company != company
    ]
    seen = set()
    fresh = []
    for n in networks or []:
        bssid = (n.get("bssid") or "").strip()
        if not bssid or bssid.lower() in seen:
            continue
        seen.add(bssid.lower())
        fresh.append({"company": company, "ssid": (n.get("ssid") or "").strip(), "bssid": bssid})

    settings.set("allowed_wifi", kept + fresh)
    settings.save(ignore_permissions=True)
    frappe.db.commit()
    return {"status": True, "data": {"count": len(fresh), "bssids": allowed_wifi_bssids(company)}}
