import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  static const _channelId = 'appe_location';

  static Future<void> initialize() async {
    try {
      // The foreground-service notification needs an existing channel, or the
      // native service crashes on creation (Android O+ / targetSdk 34+).
      const channel = AndroidNotificationChannel(
        _channelId,
        'Location tracking',
        description: 'Keeps your work location up to date',
        importance: Importance.low,
      );
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          isForegroundMode: true,
          autoStart: false,
          notificationChannelId: _channelId,
          initialNotificationTitle: 'Techbird Appe',
          initialNotificationContent: 'Location tracking active',
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
        iosConfiguration: IosConfiguration(
          onForeground: onStart,
          autoStart: false,
        ),
      );
    } catch (_) {
      // Never let location-service setup block app startup.
    }
  }

  static Future<void> start() async {
    try {
      await FlutterBackgroundService().startService();
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      FlutterBackgroundService().invoke('stopService');
    } catch (_) {}
  }
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
