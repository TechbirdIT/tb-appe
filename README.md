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
- **DocTypes & Workspace** — the data model and Desk workspace for the mobile app
  (attendance, customers, employees, expenses, reports, etc.).
- **Appe Buddy** (`ai/`) — an AI assistant baked into the app that can read data,
  write documents, and build artifacts (DocTypes, Reports, Dashboard Charts, Number
  Cards, Dashboards) on behalf of the logged-in user, always respecting Frappe
  permissions. See [`tb_appe/ai/README.md`](tb_appe/ai/README.md).

## Configuration

- Configure the AI assistant under **Appe Buddy Settings** (provider, model, and
  capability flags).
- Other app behaviour is managed via **Appe Settings**.

## License

MIT — see [`license.txt`](license.txt).

## About

Built and maintained by **TechbirdIT**. For questions, contact
`ekansh.jain@techbirdit.in`.
