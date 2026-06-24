import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_config.dart';
import 'api.dart';

/// Employee-location tracking.
///
/// Posts the device location to `appe.appe_api.storelocation` while tracking is
/// on. Uses geolocator's own location stream with an Android foreground-service
/// notification, so updates continue when the app is in the background (when
/// "Allow all the time" is granted). The server rejects updates < 2 min apart,
/// so posts are throttled to [AppConfig.locationInterval].
class LocationService {
  static StreamSubscription<Position>? _sub;
  static DateTime? _lastPost;

  /// Kept for call-site compatibility; no setup is required.
  static Future<void> initialize() async {}

  static bool get isRunning => _sub != null;

  /// Foreground location permission (while-in-use). Returns true if granted.
  static Future<bool> ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.always ||
          p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Background location permission ("Allow all the time"), needed to keep
  /// tracking when the app is not in the foreground.
  static Future<bool> ensureBackgroundPermission() async {
    if (!await ensurePermission()) return false;
    var status = await Permission.locationAlways.status;
    if (!status.isGranted) status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  static Future<bool> start() async {
    if (!await ensurePermission()) return false;
    final background = await ensureBackgroundPermission();
    await _sub?.cancel();

    final settings = background
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: AppConfig.locationInterval,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Techbird Appe',
              notificationText: 'Recording your work location',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
            intervalDuration: AppConfig.locationInterval,
          );

    await _report(); // record once immediately
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_maybePost, onError: (_) {});
    return true;
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  static void _maybePost(Position pos) {
    final now = DateTime.now();
    if (_lastPost != null &&
        now.difference(_lastPost!) < const Duration(minutes: 2)) {
      return;
    }
    _lastPost = now;
    _postPosition(pos);
  }

  static Future<void> _report() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      _lastPost = DateTime.now();
      await _postPosition(pos);
    } catch (_) {}
  }

  static Future<void> _postPosition(Position pos) async {
    try {
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
      // Swallow transient errors; the next update retries.
    }
  }
}
