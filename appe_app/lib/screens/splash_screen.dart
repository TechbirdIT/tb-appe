import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';
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
      backgroundColor: const Color(0xFFF1F2F4),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Serif wordmark with faint circular logo watermark behind it.
                SizedBox(
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: 0.06,
                        child: Image.asset('assets/images/logo.png',
                            width: 150,
                            errorBuilder: (context, error, stack) =>
                                const SizedBox.shrink()),
                      ),
                      const Text(
                        'Techbird Appe',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B2440),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Loading...',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54)),
                const SizedBox(height: 6),
                const Text('Please wait while we fetch your data',
                    style: TextStyle(color: Colors.black38)),
              ],
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 28),
              child: Text('by appetech.io',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black87)),
            ),
          ),
        ],
      ),
    );
  }
}
