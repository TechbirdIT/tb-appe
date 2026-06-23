import frappe
from frappe import _
from frappe.core.doctype.role.role import get_info_based_on_role
from frappe.email.doctype.notification.notification import Notification, get_context, json


class SendNotification(Notification):

    
    def appe_send_push_notification(self, doc, notification, receivers):
        # try:
        frappe.log_error("send_push_notification receivers",receivers)
       

        try:
            # Create new document
            notification_doc = frappe.new_doc("Mobile App Notification")
            notification_doc.title = doc.get("title") or "New Notification"
            notification_doc.message = doc.get("message") or ""
            
            # Optional JSON data
            notification_doc.data = json.dumps({
                "document_type": doc.doctype,
                "document_name": doc.name
            })

            # Add users in child table
            for user in receivers:
                if user:
                    notification_doc.append("users", {
                        "user": user
                    })

            frappe.log_error("Notification Doc",str(notification_doc))

            notification_doc.insert(ignore_permissions=True)
            notification_doc.submit()
            frappe.db.commit()

            frappe.msgprint("Mobile App Notification Created Successfully")

        except Exception as e:
            frappe.log_error("Error in create_mobile_app_notification",e)
            frappe.throw(e)

    def get_push_receiver_list(self, doc, context):
        """User IDs for Mobile Push — core get_receiver_list is for SMS (mobile_no)."""
        receiver_list = []
        for recipient in self.recipients:
            if recipient.condition:
                if not frappe.safe_eval(recipient.condition, None, context):
                    continue

            if recipient.receiver_by_document_field == "owner":
                owner = doc.get("owner")
                if owner:
                    receiver_list.append(owner)
            elif recipient.receiver_by_document_field:
                fields = recipient.receiver_by_document_field.split(",")
                if len(fields) > 1:
                    for row in doc.get(fields[1]) or []:
                        uid = row.get(fields[0])
                        if uid:
                            receiver_list.append(uid)
                else:
                    uid = doc.get(fields[0])
                    if uid:
                        receiver_list.append(uid)

            if recipient.receiver_by_role:
                receiver_list.extend(
                    get_info_based_on_role(
                        recipient.receiver_by_role, "name", ignore_permissions=True
                    )
                )

        return list(dict.fromkeys(receiver_list))

    # def validate(self):
    #     self.validate_CRM_whatsapp_settings()

    # def validate_CRM_whatsapp_settings(self):
    #     if self.enabled and self.channel == "WhatsApp" \
    #         and not frappe.db.get_single_value("CRM Whatsapp Setting", "url"):
    #         frappe.throw(_("Please enable Whatsapp settings to send WhatsApp messages"))

    def send(self, doc):
        context = get_context(doc)
        context = {"doc": doc, "alert": self, "comments": None}
        if doc.get("_comments"):
            context["comments"] = json.loads(doc.get("_comments"))

        if self.is_standard:
            self.load_standard_properties(context)

        try:
            # if self.channel == 'WhatsApp':
            #     receivers = self.get_receiver_list(doc, context)
            #     frappe.log_error('Notification Doc',str(context))
            #     send_whatsapp_msg(doc, self, receivers)

            if self.channel == 'Mobile Push Notification':
                receivers = self.get_push_receiver_list(doc, context)
                frappe.log_error('Notification Doc',str(context))
                frappe.log_error("Push notification receiver", receivers)
                # self.appe_send_push_notification(doc, , receivers)

                try:
                    notification_doc = frappe.new_doc("Mobile App Notification")
                    notification_doc.title = doc.get("title") or "New Notification"
                    notification_doc.message = doc.get("message") or ""
                    notification_doc.data = json.dumps({
                        "document_type": doc.doctype,
                        "document_name": doc.name
                    })
                    for user in receivers:
                        if user:
                            notification_doc.append("users", {
                                "user": user
                            })
                        else:
                            frappe.log_error("Push notification receiver not found", user)



                    notification_doc.insert(ignore_permissions=True)
                    notification_doc.submit()
                    frappe.msgprint("Mobile App Notification Created Successfully")

                except Exception as e:
                    frappe.log_error("Error in create_mobile_app_notification",e)
                
    

        except:
            frappe.log_error(title='Failed to send notification', message=frappe.get_traceback())

        super(SendNotification, self).send(doc)