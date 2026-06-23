# Appe — Android replica (Flutter)

A from-scratch, **buildable** replica of `com.kameshkumar.appe` (Appe v1.5.4,
build 35) set up for editing in **Android Studio** (with the Flutter plugin) or
VS Code.

## Why Flutter, not a Kotlin/Java Android project

The original Appe app is built with **Flutter**. Evidence pulled from the APK:
`libflutter.so` + `libapp.so`, an `assets/flutter_assets/` tree, and Flutter
packages (`flutter_inappwebview`, `flutter_map`, `syncfusion_flutter_pdfviewer`,
`font_awesome_flutter`, `cupertino_icons`).

The app's Dart logic is **AOT-compiled into `libapp.so`** and is *not*
recoverable as editable source — no tool turns `libapp.so` back into rebuildable
Dart. So a faithful, editable replica must be **rebuilt as a Flutter project**,
seeded with the real assets/metadata and matched to the original's behavior.
That is what this project is. Opening it in Android Studio gives you the native
Android host (`android/`) plus the editable Dart app (`lib/`).

## What was carried over verbatim from the original APK

| Item | Source in APK | Where it lives here |
|---|---|---|
| Application id | manifest | `android/app/build.gradle.kts` → `com.kameshkumar.appe` |
| Version | `versionName 1.5.4`, `versionCode 35` | `pubspec.yaml` → `1.5.4+35` |
| min/target SDK | 24 / 36 | `android/app/build.gradle.kts` |
| Launcher icons | `res/mipmap-*/ic_launcher.png` | `android/app/src/main/res/mipmap-*` |
| App images | `flutter_assets/assets/images/*` | `assets/images/` |
| Permissions | manifest | `android/app/src/main/AndroidManifest.xml` |
| Dependency set | bundled packages + permissions | `pubspec.yaml` |

## Inferred architecture (rebuilt here)

- **Connect screen** (`lib/screens/connect_screen.dart`) — user points the app at
  their Frappe / ERPNext site; remembered via `shared_preferences`.
- **WebView home** (`lib/screens/webview_home.dart`) — the core shell renders the
  Frappe site with `flutter_inappwebview`, matching how the original surfaces the
  ERP UI.
- **Location service** (`lib/services/location_service.dart`) — Appe's headline
  feature: a foreground background-service records location every 15 min and
  POSTs it to the connected site. Endpoint name is a placeholder until confirmed
  in Stage 2.

## Backend

The server side is the Frappe app cloned at the repo root (`../appe/`), the real
`appetech/appe` repository. The mobile app talks to a Frappe site running that
app (`appe_api.py`, `appe_shop_api.py`).

## How to run

```bash
cd appe_app
flutter pub get
flutter run                 # on the connected device/emulator
# or
flutter build apk --debug   # produces build/app/outputs/flutter-apk/app-debug.apk
```

Open the `appe_app/` folder in Android Studio (File → Open) with the Flutter +
Dart plugins installed.

## Status / next stages

- **Stage 1 (done):** buildable foundation — real metadata, assets, deps,
  permissions, WebView shell + native-feature skeletons.
- **Stage 2 (in progress):** recovered the **real API contract** offline from
  `libapp.so` string literals and cross-checked it against the backend
  (`../appe/appe_api.py`, `../appe/ai/api.py`). See `lib/API_CONTRACT.md`.
  Built against the real endpoints:
  - `lib/services/api.dart` — Frappe token-auth client.
  - `lib/screens/login_screen.dart` — `login_user` auth.
  - `lib/screens/dashboard_screen.dart` — sections, quick actions, ERP-desk
    WebView, location toggle, Appe Buddy FAB.
  - `lib/screens/ai_buddy_screen.dart` — AI chat via `appe.ai.api.*`.
  - `lib/screens/posts_screen.dart` — feed via `get_appe_posts`.
  - `lib/services/location_service.dart` — corrected to the real `storelocation`
    batched shape.
  - **Visual pass (started):** captured the real app live (screens in
    `../apk-work/stage2/`). No `FLAG_SECURE`, so screenshots work. Matched:
    - **Splash** (`splash_screen.dart`) — serif "Appe" wordmark, faint logo
      watermark, "Loading… / Please wait while we fetch your data",
      "by appetech.io" footer, `#F1F2F4` background.
    - **Dashboard** (`dashboard_screen.dart`) — rebuilt to the real design:
      white app bar with avatar + "Good Morning / <name>", search + violet
      Appe-Buddy sparkle + bell-with-red-badge; light-grey body; white rounded
      section cards; each item a dark-navy (`#1B2440`) monogram circle + label.
      Monogram rule reproduced exactly (e.g. "New Sales Order"→"NS",
      "Leads"→"LE", "Check-in / Check-out"→"C/"). Server-driven from
      `get_dashboard_sections` (`Mobile App Dashboard` → items; item fields:
      `label`, `linked_doctype`, `report_name`, `screen_name`, `web_url`).
    Real sections seen: Quick Actions, My Day, Leads & Pipeline, My Expenses,
    Announcements, Key Metrics.
  - **Still to build:** OTP + face-login, employee check-in, expenses, shop/
    ordering, scanner, PDF, map; and finer visual matching of inner screens.

## Firebase / push

No Firebase config is embedded from the original (it belongs to the vendor's
project). To enable FCM push, add your own `google-services.json` and apply the
Google Services Gradle plugin.

## Reverse-engineering artifacts

Raw decompiled output for reference lives in `../apk-work/`:
`decompiled/jadx` (readable Java/Kotlin host), `decompiled/apktool`
(smali + resources + manifest), `extracted/` (flutter assets), `apks/` (the
pulled split APKs).
