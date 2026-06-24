import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';
import '../services/biometric_service.dart';
import '../theme.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Launch splash — mirrors the real Appe splash: a serif "Appe" wordmark with a
/// faint circular logo watermark, a loading caption, and the "by appetech.io"
/// footer. Decides whether to resume into the dashboard (saved token) or show
/// login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final prefs = await SharedPreferences.getInstance();
    final hasToken = prefs.getString('appe_token') != null;
    // If we have saved credentials, silently refresh the token so a rotated
    // secret never bounces the user to the login screen.
    final dwell = Future<void>.delayed(const Duration(milliseconds: 1200));
    bool authed = hasToken;
    if (await AppeApi.hasSavedCredentials()) {
      authed = (await AppeApi.tryAutoLogin()) != null || hasToken;
    }
    await dwell; // keep the splash visible briefly, like the real app
    if (!mounted) return;

    // Biometric gate: when enabled, require a successful unlock before the app.
    if (authed && await BiometricService.isEnabled()) {
      final ok = await BiometricService.authenticate();
      if (!ok) {
        if (mounted) setState(() => _locked = true);
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            authed ? const DashboardScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryHover],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.85, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusLg),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 24,
                              offset: const Offset(0, 10)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text('TA',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 38,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text('Techbird Appe',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  const Text('Frappe, anywhere you go.',
                      style: TextStyle(color: Colors.white60)),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_locked)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        onPressed: () {
                          setState(() => _locked = false);
                          _decide();
                        },
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Unlock'),
                      )
                    else
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white70),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    const Text('by appetech.io',
                        style: TextStyle(
                            color: Colors.white38,
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
