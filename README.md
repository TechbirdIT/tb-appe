# Techbird Appe

A Frappe/ERPNext mobile stack: the **Frappe backend app** plus a **Flutter mobile client** (Techbird Appe), built as a working, editable rebuild of the Appe mobile experience.

## Repository layout

| Path | What it is |
|------|------------|
| `appe/` | The **Frappe backend app** (server-side). Installs into a Frappe/ERPNext site via `bench get-app` / `bench install-app appe`. Provides the mobile REST API (`appe_api.py`, `appe_shop_api.py`), the doctypes, and the "Appe Buddy" AI assistant (`ai/`). MIT licensed — see `license.txt`. |
| `appe_app/` | The **Flutter mobile client** — open this in Android Studio (with the Flutter + Dart plugins) or VS Code. This is the editable app. |

> Reverse-engineering scratch (pulled APKs, decompiled output) is intentionally **not** committed — see `.gitignore`.

## The mobile client (`appe_app/`)

A Flutter app that talks to a Frappe site running the `appe` backend. Built screen-by-screen against the real API contract.

**Implemented screens / features**
- **Splash** → silent auto-login from saved credentials
- **Login** — `login_user` token auth, with stored site + email
- **Dashboard** — server-driven sections (`get_dashboard_sections`) rendered as monogram tiles
- **Check-in / out** — `employee_checkin(_status)` with GPS
- **Leave balance** — `leave_balance`
- **Posts feed** — `get_appe_posts`
- **Notifications** — Unread / Read / All tabs over `Notification Log`, with detail view + mark-as-read
- **Profile** — `user_details`, with sign-out
- **Appe Buddy** AI chat — `appe.ai.api.*`
- **Background location tracking** — 15-minute foreground service posting to `storelocation`
- **ERP fallback** — any unbuilt screen opens in an in-app WebView

**Resilience**
- The API token is rotated by the backend on every login; the client **silently re-authenticates** with securely-stored credentials and retries, so a stale token never bounces you to the login screen.
- Auth/permission failures surface as clean messages, not raw server tracebacks.

See `appe_app/REPLICA_NOTES.md` and `appe_app/lib/API_CONTRACT.md` for the full build notes and the recovered API contract.

## Running the mobile client

```bash
cd appe_app
flutter pub get
flutter run            # on a connected device/emulator
# or
flutter build apk --debug
```

App id `com.kameshkumar.appe.replica`, so it installs alongside the original app without conflict.

## Running the backend

```bash
cd $PATH_TO_YOUR_BENCH
bench get-app /path/to/appe        # or the git URL
bench --site your-site install-app appe
```

## License

The backend (`appe/`) is MIT — see `license.txt`. The Flutter client in `appe_app/` is original work in this repository.
