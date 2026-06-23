# Appe API contract (recovered)

Base site (default): `https://appetech.io` — recovered from `libapp.so` string
literals; users can point at any Frappe/ERPNext site. Server-side signatures
confirmed against the cloned backend at `../appe/appe_api.py`.

Auth: Frappe token auth. `login_user` returns `data.token = "token <key>:<secret>"`,
sent as the `Authorization` header on every later call.

## App-specific (`appe.appe_api.*`)
| Endpoint | Params | Returns |
|---|---|---|
| `login_user` | `usr`, `pwd` | `{status, type, message, data:{token,user,email,settings,userData,erpnext_exists}}` |
| `sendOTP` | — | `{status, message}` (stub) |
| `verifyOTP` | `usr`, `pwd` | `{status, message, data:{token,user,settings}}` |
| `storelocation` | `locations[]` (each `{latitude,longitude,timestamp,device_info{...}}`) | `{status,message}`; server rejects < 2 min apart |
| `get_dashboard_sections` | — (session) | dashboard layout |
| `get_module_data` | — | modules |
| `gettasks_and_request_and_attendancedata` | — | tasks + requests + attendance |
| `leave_balance` | — | leave balances |
| `employee_details` / `user_details` | — | profile |
| `employee_checkin` / `employee_checkin_status` | checkin payload | check-in state |
| `get_appe_posts` | `limit_start`, `limit_page_length` | feed posts |
| `create_appe_post` | `title`, `content` | new post |
| `share_remove` / `remove_assignment` | ids | — |
| `receive_message` / `get_chat_messages` | chat payload | messaging |

## Face login
`appe.identify_employee_from_image.identify_employee` — image-based employee
identification (the ML Kit face-detection native lib).

## AI "Appe Buddy" (`appe.ai.api.*`)
`send_message`, `list_conversations`, `get_conversation`, `rename_conversation`,
`pin_conversation`, `delete_conversation`, `me`, `test_connection`.

## Standard Frappe desk (used via the WebView / report screens)
`frappe.client.*`, `frappe.desk.form.load.getdoc/getdoctype`,
`frappe.desk.reportview.get/get_count`, `frappe.desk.query_report.run`,
`frappe.desk.search.*`, dashboard chart/number-card endpoints, ERPNext
`get_item_details`. Full list: `../apk-work/stage2/api_endpoints.md`.
