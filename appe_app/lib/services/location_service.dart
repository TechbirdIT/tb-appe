import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../app_config.dart';
import 'api.dart';

/// Employee-location tracking.
///
/// Records the device location every [AppConfig.locationInterval] while the app
/// is running and posts a batched `locations` array to the connected Frappe
/// site via `appe.appe_api.storelocation` (the server rejects updates more
/// frequent than 2 minutes).
///
/// This uses an in-app timer rather than an Android foreground service: on
/// Android 14+ a background-started location foreground-service is disallowed
/// without granted location permission and crashes the process, so tracking is
/// scoped to while the app is open. (A WorkManager-based background variant can
/// be added later behind a proper permission flow.)
class LocationService {
  static Timer? _timer;

  /// Kept for call-site compatibility; no setup is required now.
  static Future<void> initialize() async {}

  static bool get isRunning => _timer != null;

  static Future<bool> start() async {
    if (!await _ensurePermission()) return false;
    _timer?.cancel();
    await _report(); // record once immediately
    _timer = Timer.periodic(AppConfig.locationInterval, (_) => _report());
    return true;
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  static Future<bool> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _report() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final api = await AppeApi.create();
      if (!api.isAuthenticated) return;
      await api.storeLocations([
        {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'device_info': {'gps_status': true},
        }
      ]);
    } catch (_) {
      // Swallow transient errors; the next tick retries.
    }
  }
}
