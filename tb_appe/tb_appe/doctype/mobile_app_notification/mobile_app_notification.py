# Copyright (c) 2025, TechbirdIT and contributors
# For license information, please see license.txt

import frappe
import json
import requests
from frappe.model.document import Document


class MobileAppNotification(Document):
	def before_submit(self):
		onesignal_api_key = frappe.db.get_single_value('Appe Settings','onesignal_api_key')
		app_id = frappe.db.get_single_value('Appe Settings','onesignal_app_id')

		if onesignal_api_key and app_id:
			url = "https://api.onesignal.com/notifications?c=push"
			# New OneSignal REST keys (os_v2_app_...) authenticate with the "Key"
			# scheme; legacy keys use "Basic". Support both.
			scheme = "Key" if onesignal_api_key.startswith("os_v2_") else "Basic"
			headers = {
				"Content-Type": "application/json; charset=utf-8",
				"Authorization": f"{scheme} {onesignal_api_key}"
			}
			# Target by external id == Frappe user (the app calls OneSignal.login
			# with the signed-in user). include_aliases is the current API; the
			# legacy include_external_user_ids is deprecated.
			receipt = [str(d.user) for d in self.users if d.user]
			payload = {
				"app_id": app_id,
				"target_channel": "push",
				"include_aliases": {"external_id": receipt},

				"headings": {"en": self.title},
				"contents": {"en": self.message},
			}
			
			if self.big_picture:
				site_url = frappe.utils.get_url()
				big_picture = f"{site_url}{str(self.big_picture)}"
				payload["big_picture"] = big_picture
				payload["ios_attachments"] = {"id": big_picture}


			j = json.dumps(payload)
			# frappe.log_error("Sending OneSignal Payload", json.dumps(payload))
			response = requests.post(url, data=j, headers=headers)
			frappe.log_error("OneSignal Response", f"{response.status_code}: {response.text}")
		else:
			frappe.throw("OneSignal API Key or App ID not configured in Appe Settings")