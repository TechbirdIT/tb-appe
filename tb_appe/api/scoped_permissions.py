# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
Scope-aware document permissions
================================
HRMS role permissions let any Employee READ every Employee Checkin, so a
line manager browsing the check-in list (mobile DoctypeListScreen or the
desk) saw the whole company's punches. These hooks narrow list queries and
single-doc reads to the caller's supervisory scope
(``hotel_core.resolve_employee_scope``):

  * scope ``None``  -> HR / System Manager / Administrator: unrestricted;
  * scope ``[...]`` -> exactly those employees (always includes self);
  * scope ``[]``    -> no employee record: nothing.

They only ever NARROW access — Frappe applies them on top of the normal
role permissions, and gateway endpoints that use ``ignore_permissions``
after their own scope checks are unaffected.
"""

import frappe

from tb_appe.integrations import hotel_core


def _scope(user):
    user = user or frappe.session.user
    if user == "Administrator":
        return None
    return hotel_core.resolve_employee_scope(user)


def employee_checkin_query(user):
    scope = _scope(user)
    if scope is None:
        return ""
    if not scope:
        return "1=0"
    emps = ", ".join(frappe.db.escape(e) for e in scope)
    return f"`tabEmployee Checkin`.`employee` in ({emps})"


def employee_checkin_has_permission(doc, ptype=None, user=None):
    scope = _scope(user)
    if scope is None:
        return True
    return doc.employee in scope
