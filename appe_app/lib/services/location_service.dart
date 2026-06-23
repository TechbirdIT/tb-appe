import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../app_config.dart';
import 'api.dart';

/// Background employee-location tracking — Appe's headline feature.
///
/// Records the device location on [AppConfig.locationInterval] and posts a
/// batched `locations` array to the connected Frappe site via
/// `appe.appe_api.storelocation` (see backend `storelocation()` — the server
/// rejects updates more frequent than 2 minutes).
class LocationService {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: false,
        notificationChannelId: 'appe_location',
        initialNotificationTitle: 'Techbird Appe',
        initialNotificationContent: 'Location tracking active',
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        autoStart: false,
      ),
    );
  }

  static Future<void> start() => FlutterBackgroundService().startService();

  static Future<void> stop() async =>
      FlutterBackgroundService().invoke('stopService');
}

/// Entry point for the background isolate.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  service.on('stopService').listen((_) => service.stopSelf());

  Timer.periodic(AppConfig.locationInterval, (_) async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final api = await AppeApi.create();
      if (!api.isAuthenticated) return;
      await api.storeLocations([
        {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          // device_info fields mirror what the backend reads off each record.
          'device_info': {
            'gps_status': true,
          },
        }
      ]);
    } catch (_) {
      // Swallow transient errors; the next tick retries.
    }
  });
}
