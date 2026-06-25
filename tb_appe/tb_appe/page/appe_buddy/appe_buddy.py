# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

import frappe


@frappe.whitelist()
def get_meta():
	"""Return capabilities + default model info for the chat page header."""
	from tb_appe.ai import api as buddy_api

	return buddy_api.settings_public()
