/// App-wide configuration for the Appe replica.
///
/// The original Appe app connects to a Frappe / ERPNext site. Users register at
/// appetech.io and point the app at their own Frappe instance, so the server URL
/// is stored at runtime (see [ConnectScreen]) rather than hard-coded here.
class AppConfig {
  static const String appName = 'Techbird Appe';

  /// Default site shown on the connect screen. Replace with your own Frappe URL.
  static const String defaultSiteUrl = 'https://appetech.io';

  /// SharedPreferences keys.
  static const String prefSiteUrl = 'appe_site_url';
  static const String prefLastUser = 'appe_last_user';

  /// How often the background service records employee location.
  /// The original app stores location every 15 minutes.
  static const Duration locationInterval = Duration(minutes: 15);
}
