import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional biometric (fingerprint / face) app lock.
///
/// When enabled, the splash gate requires a successful biometric auth before
/// revealing the app. The preference is stored locally.
class BiometricService {
  static final _auth = LocalAuthentication();
  static const _kEnabled = 'appe_biometric_enabled';

  /// Whether the device can actually do biometric auth.
  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  /// Prompts for biometric auth. Returns true on success.
  static Future<bool> authenticate(
      [String reason = 'Unlock Techbird Appe']) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device PIN/pattern fallback
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Enabling requires a successful auth first; disabling is immediate.
  static Future<bool> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      final ok = await authenticate('Confirm to enable biometric lock');
      if (!ok) return false;
    }
    await prefs.setBool(_kEnabled, enabled);
    return true;
  }
}
