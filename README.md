# TB Appe

TB Appe is TechBird's Frappe/ERPNext mobile companion backend app. It exposes the
mobile REST API, the supporting DocTypes, and the **Appe Buddy** AI assistant that
power the TB Appe mobile client — letting your team manage business operations on
the go: check-ins, attendance, expenses, leads, posts, notifications, and more.

> The companion **Flutter mobile app** lives in a separate repository,
> [`tb-appe-mobile`](../tb-appe-mobile). This repository contains only the
> Frappe/ERPNext backend app (`tb_appe`).

## Requirements

- Frappe Framework v15 or v16 (this app is v16 compatible)
- A working [Frappe Bench](https://github.com/frappe/bench) environment
- Python 3.10+
- ERPNext is optional — Appe Buddy auto-loads ERPNext-specific AI tools when ERPNext
  is installed on the site, but the core app does not require it.

## Installation

From your bench directory:

```bash
# 1. Fetch the app into your bench
bench get-app <repo-url>

# 2. Install it on your site
bench --site your-site.localhost install-app tb_appe
```

After installation, build and clear cache if needed:

```bash
bench build --app tb_appe
bench --site your-site.localhost clear-cache
```

## What's included

- **Mobile REST API** (`appe_api.py`, `appe_shop_api.py`) — login, dashboard
  sections, check-in/out, leave balance, posts feed, notifications, profile, and
  location tracking endpoints consumed by the mobile client.
- **RBAC HRMS gateway** (`api/hrms_gateway.py`, `api/rbac.py`) — a stable,
  permission-aware surface the mobile app calls for HRMS features. `my_*` reads
  are pinned to the caller's own employee (no over-fetching), while team,
  approval, and directory endpoints reuse the same hierarchical scope the Desk
  enforces. `rbac.get_me` returns a server-derived archetype plus capability
  flags (e.g. `can_view_payroll`, `can_announce`) so the client can tailor its
  UI without hard-coding roles. Company announcements (`announce`) are gated to
  admin / management roles (`rbac._ANNOUNCE_ROLES`).
- **Config-driven role dashboards** — `Mobile App Dashboard` / `Mobile App
  Module` carry RBAC targeting (archetype checks + role-profile / role /
  department lists); `get_dashboard_sections` / `get_module_data` filter by the
  caller. When `tb_hotel_core` is installed, the gateway proxies its scoped HRMS
  (`api/hrms/*`, `mobile_hrms`) in-process; otherwise it falls back to generic
  ERPNext/HRMS.
- **Approvals (hybrid, `pending_approvals`)** — a line manager approves their
  team; HR/Admin can approve anything; HR's and the GM's own requests route to
  the Admin (no self-approval). Covers leave, expense, shift and attendance.
- **Directory & location** — `directory` (all employees in scope), plus
  `employee_route` + cached OSM/Nominatim reverse geocoding (`api/geocode.py`)
  for the tracking map; the Desk **Employee Tracking** page uses Leaflet/OSM.
- **Create forms** (`api/forms.py`) — permission-gated, meta-driven document
  creation the app renders (e.g. Shift Assignment) — only doctypes the user may
  create are offered.
- **Push** — company announcements fan out a native push to every employee via
  the existing `Mobile App Notification` → **OneSignal** path (targets by
  external id == Frappe user). Configure `onesignal_app_id` + `onesignal_api_key`
  in *Appe Settings*.
- **DocTypes & Workspace** — the data model and the **Appe** Desk workspace
  (attendance, customers, employees, expenses, reports, etc.), reachable at
  [`/app/appe`](/app/appe).
- **Guided setup** — a **TB Appe Setup** onboarding wizard on the Appe workspace
  walks you through every section: settings, employees, activity & expense types,
  the mobile dashboard/modules/screens, customers, leads, posts, push
  notifications, and the Appe Buddy AI assistant.
- **Appe Buddy** (`ai/`) — an AI assistant baked into the app that can read data,
  write documents, and build artifacts (DocTypes, Reports, Dashboard Charts, Number
  Cards, Dashboards) on behalf of the logged-in user, always respecting Frappe
  permissions. See [`tb_appe/ai/README.md`](tb_appe/ai/README.md).

## Configuration

- Configure the AI assistant under **Appe Buddy Settings** (provider, model, and
  capability flags).
- Other app behaviour is managed via **Appe Settings** — check-in policy, live
  location tracking, **OneSignal** (`onesignal_app_id` + REST `onesignal_api_key`)
  for push, and the mobile dashboard/module RBAC targeting.

## Local demo data (DEV ONLY — never on production)

Idempotent seeds under `tb_appe/setup/` populate a StayBird-style demo org so
the role-tailored app can be exercised end to end:

```bash
# 20 users + employees, one per SB role profile, wired into a hierarchy
bench --site <site> execute tb_appe.setup.seed_rbac_demo.execute
# role-targeted Mobile App Dashboard sections (per archetype)
bench --site <site> execute tb_appe.setup.seed_dashboards.execute
# leave allocations, attendance, check-ins, payslips, pending requests,
# and the airtight approver hierarchy (HR/GM -> Admin)
bench --site <site> execute tb_appe.setup.seed_hrms_demo.execute
```

Each has a matching `purge`. Demo logins are `<slug>@sb.appe.local` with a shared
demo password. Requires `tb_hotel_core` (for the SB role profiles + scoped HRMS).

## First-run setup

Open the **Appe** workspace at [`/app/appe`](/app/appe) and follow the **TB Appe
Setup** onboarding card at the top. It steps through each feature section:

1. Configure Appe Settings (check-in, tracking, OneSignal, Maps)
2. Add Employee
3. Set up Daily Activity Types
4. Set up Expense Types
5. Configure the Mobile App Dashboard
6. Configure Mobile App Modules
7. Design Mobile Screens
8. Add a Customer
9. Capture your first Lead
10. Publish your first Post
11. Configure Push Notifications
12. Configure Appe Buddy (AI)
13. Open Appe Buddy
14. View Employee Tracking

> The onboarding only appears while **Enable Onboarding** is on under
> *System Settings*. After editing client assets (e.g. the Appe Buddy panel),
> run `bench build --app tb_appe` and `bench --site <site> clear-cache` so the
> Desk loads the rebuilt bundle.

## License

MIT — see [`license.txt`](license.txt).

## About

Built and maintained by **TechbirdIT**. For questions, contact
`ekansh.jain@techbirdit.in`.
