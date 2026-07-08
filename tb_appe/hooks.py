app_name = "tb_appe"
app_title = "TB Appe"
app_publisher = "TechbirdIT"
app_description = "TB Appe is TechBird's Frappe/ERPNext mobile companion app. It provides a seamless and efficient way to manage your business operations on the go, with a user-friendly interface and powerful features to access and control your data, collaborate with your team, and stay connected with your customers from anywhere, at any time."
app_email = "ekansh.jain@techbirdit.in"
app_license = "mit"
app_home = "/app/appe"

# Apps
# ------------------

# required_apps = []
after_install = "tb_appe.setup.after_install.after_install"
after_uninstall = "tb_appe.setup.uninstall.after_uninstall"
# before_uninstall = "tb_appe.setup.uninstall.after_uninstall"


# Each item in the list will be shown as an app in the apps page
add_to_apps_screen = [
	{
		"name": "tb_appe",
		"logo": "/assets/tb_appe/images/appe_logo.png",
		"title": "TB Appe",
		"route": "/app/appe",
		# "has_permission": "tb_appe.api.permission.has_app_permission"
	}
]

# Includes in <head>
# ------------------

# include js, css files in header of desk.html

app_include_css = ["appe_buddy.bundle.css"]
app_include_js = ["appe_buddy_panel.bundle.js"]

# include js, css files in header of web template
# web_include_css = "/assets/tb_appe/css/tb_appe.css"
# web_include_js = "/assets/tb_appe/js/tb_appe.js"

# include custom scss in every website theme (without file extension ".scss")
# website_theme_scss = "tb_appe/public/scss/website"

# include js, css files in header of web form
# webform_include_js = {"doctype": "public/js/doctype.js"}
# webform_include_css = {"doctype": "public/css/doctype.css"}

# include js in page
# page_js = {"page" : "public/js/file.js"}

# include js in doctype views
# doctype_js = {"doctype" : "public/js/doctype.js"}
doctype_js = {"Notification" : "public/js/notification.js"}
# doctype_list_js = {"doctype" : "public/js/doctype_list.js"}
# doctype_tree_js = {"doctype" : "public/js/doctype_tree.js"}
# doctype_calendar_js = {"doctype" : "public/js/doctype_calendar.js"}

# Svg Icons
# ------------------
# include app icons in desk
# app_include_icons = "tb_appe/public/icons.svg"

# Home Pages
# ----------

# application home page (will override Website Settings)
# home_page = "login"

# website user home page (by Role)
# role_home_page = {
# 	"Role": "home_page"
# }

# Generators
# ----------

# automatically create page for each record of this doctype
# website_generators = ["Web Page"]

# Jinja
# ----------

# add methods and filters to jinja environment
# jinja = {
# 	"methods": "tb_appe.utils.jinja_methods",
# 	"filters": "tb_appe.utils.jinja_filters"
# }

# Installation
# ------------

# before_install = "tb_appe.install.before_install"
# after_install = "tb_appe.install.after_install"

# Uninstallation
# ------------

# before_uninstall = "tb_appe.uninstall.before_uninstall"
# after_uninstall = "tb_appe.uninstall.after_uninstall"

# Integration Setup
# ------------------
# To set up dependencies/integrations with other apps
# Name of the app being installed is passed as an argument

# before_app_install = "tb_appe.utils.before_app_install"
# after_app_install = "tb_appe.utils.after_app_install"

# Integration Cleanup
# -------------------
# To clean up dependencies/integrations with other apps
# Name of the app being uninstalled is passed as an argument

# before_app_uninstall = "tb_appe.utils.before_app_uninstall"
# after_app_uninstall = "tb_appe.utils.after_app_uninstall"

# Desk Notifications
# ------------------
# See frappe.core.notifications.get_notification_config

# notification_config = "tb_appe.notifications.get_notification_config"

# Permissions
# -----------
# Permissions evaluated in scripted ways

# permission_query_conditions = {
# 	"Event": "frappe.desk.doctype.event.event.get_permission_query_conditions",
# }
#
# has_permission = {
# 	"Event": "frappe.desk.doctype.event.event.has_permission",
# }

# DocType Class
# ---------------
# Override standard doctype classes

override_doctype_class = {
	# "ToDo": "custom_app.overrides.CustomToDo"
	"Notification": "tb_appe.overrides.notification.SendNotification"

}

# Document Events
# ---------------
# Hook on document methods and events

# doc_events = {
# 	"*": {
# 		"on_update": "method",
# 		"on_cancel": "method",
# 		"on_trash": "method"
# 	}
# }

doc_events = {
	"Prepared Report": {
		"on_update": "tb_appe.appe_api.update_appe_reports",
	}
}

# Scheduled Tasks
# ---------------

scheduler_events = {
	"daily": [
		# Aggregate yesterday's raw Employee Location points into
		# Appe Employee Route Summary (desk Employee Tracking page).
		"tb_appe.api.tasks.create_daily_route_summary",
	],
}

# scheduler_events = {
# 	"all": [
# 		"tb_appe.tasks.all"
# 	],
# 	"daily": [
# 		"tb_appe.tasks.daily"
# 	],
# 	"hourly": [
# 		"tb_appe.tasks.hourly"
# 	],
# 	"weekly": [
# 		"tb_appe.tasks.weekly"
# 	],
# 	"monthly": [
# 		"tb_appe.tasks.monthly"
# 	],
# }

# Testing
# -------

# before_tests = "tb_appe.install.before_tests"

# Overriding Methods
# ------------------------------
#
# override_whitelisted_methods = {
# 	"frappe.desk.doctype.event.event.get_events": "tb_appe.event.get_events"
# }
#
# each overriding function accepts a `data` argument;
# generated from the base implementation of the doctype dashboard,
# along with any modifications made in other Frappe apps
# override_doctype_dashboards = {
# 	"Task": "tb_appe.task.get_dashboard_data"
# }

# exempt linked doctypes from being automatically cancelled
#
# auto_cancel_exempted_doctypes = ["Auto Repeat"]

# Ignore links to specified DocTypes when deleting documents
# -----------------------------------------------------------

# ignore_links_on_delete = ["Communication", "ToDo"]

# Request Events
# ----------------
# before_request = ["tb_appe.utils.before_request"]
# after_request = ["tb_appe.utils.after_request"]

# Job Events
# ----------
# before_job = ["tb_appe.utils.before_job"]
# after_job = ["tb_appe.utils.after_job"]

# User Data Protection
# --------------------

# user_data_fields = [
# 	{
# 		"doctype": "{doctype_1}",
# 		"filter_by": "{filter_by}",
# 		"redact_fields": ["{field_1}", "{field_2}"],
# 		"partial": 1,
# 	},
# 	{
# 		"doctype": "{doctype_2}",
# 		"filter_by": "{filter_by}",
# 		"partial": 1,
# 	},
# 	{
# 		"doctype": "{doctype_3}",
# 		"strict": False,
# 	},
# 	{
# 		"doctype": "{doctype_4}"
# 	}
# ]

# Authentication and authorization
# --------------------------------

# auth_hooks = [
# 	"tb_appe.auth.validate"
# ]

# Automatically update python controller files with type annotations for this app.
# export_python_type_annotations = True

# default_log_clearing_doctypes = {
# 	"Logging DocType Name": 30  # days to retain logs
# }

fixtures = ["Property Setter"]