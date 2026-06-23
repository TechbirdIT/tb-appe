import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../services/api.dart';
import 'dashboard_screen.dart';

/// Native login screen replicating Appe's auth flow:
/// user enters their site + credentials, which hit
/// `appe.appe_api.login_user` and yield a Frappe API token.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _site = TextEditingController(text: AppConfig.defaultSiteUrl);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _maybeResume();
  }

  Future<void> _maybeResume() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('appe_token') != null && mounted) {
      _go();
      return;
    }
    // Prefill the site + login id from the last session.
    final site = await AppeApi.savedSite();
    final usr = await AppeApi.savedLoginUsr();
    if (mounted) {
      setState(() {
        if (site != null && site.isNotEmpty) _site.text = site;
        if (usr != null) _user.text = usr;
      });
    }
  }

  Future<void> _login() async {
    var site = _site.text.trim();
    if (!site.startsWith('http')) site = 'https://$site';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppeApi.login(site, _user.text.trim(), _pass.text);
      if (mounted) _go();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach $site');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _go() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png',
                    height: 88,
                    errorBuilder: (c, e, s) =>
                        const Icon(Icons.apps, size: 88)),
                const SizedBox(height: 12),
                const Text('Techbird Appe',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                const Text('Frappe, anywhere you go.'),
                const SizedBox(height: 28),
                TextField(
                  controller: _site,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Site URL',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.public),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(
                    labelText: 'Email or username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _login,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Login'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
