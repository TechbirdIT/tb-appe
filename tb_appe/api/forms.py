# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
Generic mobile create-forms
===========================
A permission-gated, meta-driven create surface for a curated set of HRMS
doctypes (Shift Assignment, Attendance/Shift Requests, etc.). The app asks
which doctypes the user may create (`creatable_doctypes`), fetches a trimmed
field list to render (`form_meta`), searches Link targets (`link_options`), and
submits (`create_doc`). Every call enforces Frappe's own create/read
permission — so a user only ever sees and creates what their roles allow, and
Link options for Employee are auto-scoped by tb_hotel_core's permission query.
"""

import json

import frappe
from frappe import _

# Doctypes the mobile app offers a create form for. Extend as needed.
SUPPORTED = [
    "Shift Assignment",
    "Attendance Request",
    "Shift Request",
    "Leave Application",
    "Expense Claim Type",
]

# Field types the mobile form knows how to render.
_RENDERABLE = {
    "Data", "Small Text", "Text", "Text Editor", "Select", "Link",
    "Date", "Datetime", "Time", "Int", "Float", "Currency", "Check", "Percent",
}

# Always-skip fields (system / layout / not user-editable on create).
_SKIP = {"amended_from", "naming_series"}


def _ok(data=None):
    return {"status": True, "data": data}


@frappe.whitelist()
def creatable_doctypes():
    """The supported doctypes the caller has create permission for."""
    out = []
    for dt in SUPPORTED:
        if frappe.db.exists("DocType", dt) and frappe.has_permission(dt, ptype="create"):
            out.append({"doctype": dt, "label": _(dt)})
    return _ok(out)


@frappe.whitelist()
def form_meta(doctype):
    """Trimmed, renderable field list for a create form."""
    if doctype not in SUPPORTED:
        frappe.throw(_("{0} is not available as a mobile form").format(doctype))
    frappe.has_permission(doctype, ptype="create", throw=True)

    meta = frappe.get_meta(doctype)
    fields = []
    for df in meta.fields:
        if df.fieldtype not in _RENDERABLE:
            continue
        if df.hidden or df.read_only or df.fieldname in _SKIP:
            continue
        # Keep the form focused: mandatory fields, list-view fields, or a few
        # well-known HR fields. Everything else is left to server defaults.
        keep = (
            df.reqd
            or df.in_list_view
            or df.bold
            or df.fieldname
            in ("employee", "from_date", "to_date", "start_date", "end_date",
                "shift_type", "status", "leave_type", "reason", "date")
        )
        if not keep:
            continue
        fields.append(
            {
                "fieldname": df.fieldname,
                "label": df.label or df.fieldname,
                "fieldtype": df.fieldtype,
                "options": df.options,
                "reqd": int(df.reqd or 0),
                "default": df.default,
            }
        )
    return _ok({"doctype": doctype, "title": _(doctype), "fields": fields})


@frappe.whitelist()
def link_options(doctype, txt=""):
    """Search a Link target, permission-scoped (so Employee is team-scoped)."""
    if not frappe.has_permission(doctype, ptype="read"):
        return _ok([])
    meta = frappe.get_meta(doctype)
    title_field = meta.title_field or None
    fields = ["name"] + ([title_field] if title_field else [])
    filters = {}
    rows = frappe.get_list(
        doctype,
        or_filters=(
            [["name", "like", f"%{txt}%"]]
            + ([[title_field, "like", f"%{txt}%"]] if title_field else [])
        )
        if txt
        else filters,
        fields=fields,
        limit=20,
        order_by="modified desc",
    )
    return _ok(
        [
            {"value": r.get("name"), "label": (r.get(title_field) if title_field else None) or r.get("name")}
            for r in rows
        ]
    )


@frappe.whitelist(methods=["POST"])
def create_doc(doctype, values):
    """Insert a document, enforcing create permission."""
    if doctype not in SUPPORTED:
        frappe.throw(_("{0} is not available as a mobile form").format(doctype))
    frappe.has_permission(doctype, ptype="create", throw=True)
    if isinstance(values, str):
        values = json.loads(values or "{}")
    values.pop("doctype", None)
    doc = frappe.get_doc({"doctype": doctype, **values})
    doc.insert()  # respects permissions + validation
    frappe.db.commit()
    return _ok({"name": doc.name, "doctype": doctype})
