import 'package:flutter/material.dart';

import '../services/api.dart';
import 'login_screen.dart';

/// User profile — `appe.appe_api.user_details`. Shows the signed-in user's
/// info and holds the **Logout** action (moved here off the dashboard avatar,
/// which now opens this screen instead of signing out).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _navy = Color(0xFF1B2440);

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _u = {};
  String _site = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await AppeApi.create();
      _site = api.site;
      final res = await api.userDetails();
      final data = (res is Map ? (res['data'] ?? res) : res);
      setState(() {
        _u = data is Map ? data.cast<String, dynamic>() : {};
        _loading = false;
      });
    } on AuthException {
      setState(() {
        _error = 'Your session has expired.';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You will need to enter your credentials again to sign back in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await AppeApi.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String get _name =>
      (_u['full_name'] ?? _u['username'] ?? _u['email'] ?? 'User').toString();

  String? _imageUrl() {
    final img = (_u['user_image'] ?? '').toString();
    if (img.isEmpty) return null;
    return img.startsWith('http') ? img : '$_site$img';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 24),
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: _navy,
                    backgroundImage: _imageUrl() != null
                        ? NetworkImage(_imageUrl()!)
                        : null,
                    child: _imageUrl() == null
                        ? Text(
                            _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 32))
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(_name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                if ((_u['email'] ?? '').toString().isNotEmpty)
                  Center(
                    child: Text((_u['email']).toString(),
                        style: const TextStyle(color: Colors.black54)),
                  ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                _info('Mobile', _u['mobile_no']),
                _info('Username', _u['username']),
                _info('Location', _u['location']),
                _info('User type', _u['user_type']),
                _info('Time zone', _u['time_zone']),
                _info('Site', _site),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.all(14),
                    ),
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _info(String label, dynamic value) {
    final v = (value ?? '').toString();
    if (v.isEmpty) return const SizedBox.shrink();
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(color: Colors.black54)),
      subtitle: Text(v, style: const TextStyle(color: Colors.black87)),
    );
  }
}
