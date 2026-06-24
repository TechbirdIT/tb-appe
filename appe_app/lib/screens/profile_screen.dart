import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/api.dart';
import '../services/biometric_service.dart';
import '../theme.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';

/// User profile — `appe.appe_api.user_details`. Mirrors the original Appe
/// profile: a Contact card, a Biometric Lock toggle, and an Account section
/// with Change Password + Logout.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _u = {};
  String _site = '';
  String _version = '';
  bool _bioAvailable = false;
  bool _bioEnabled = false;

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
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _bioAvailable = await BiometricService.isAvailable();
      _bioEnabled = await BiometricService.isEnabled();
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

  Future<void> _toggleBiometric(bool on) async {
    final ok = await BiometricService.setEnabled(on);
    if (mounted) {
      setState(() => _bioEnabled = ok ? on : _bioEnabled);
      if (!ok && on) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric not confirmed')),
        );
      }
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
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

  String get _initials {
    final parts = _name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return _name.isNotEmpty ? _name[0].toUpperCase() : '?';
  }

  String? _imageUrl() {
    final img = (_u['user_image'] ?? '').toString();
    if (img.isEmpty) return null;
    return img.startsWith('http') ? img : '$_site$img';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.xxl),
              children: [
                _avatarBlock(),
                const SizedBox(height: AppSpacing.xl),
                if (_error != null) _errorBanner(),
                _contactCard(),
                if (_bioAvailable) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _biometricCard(),
                ],
                const SizedBox(height: AppSpacing.lg),
                _accountCard(),
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Text('App Version $_version',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _avatarBlock() {
    final img = _imageUrl();
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.primary,
            backgroundImage: img != null ? NetworkImage(img) : null,
            child: img == null
                ? Text(_initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700))
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(_name,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700)),
        if ((_u['email'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text((_u['email']).toString(),
              style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ],
    );
  }

  Widget _errorBanner() => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.dangerSoft,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(_error!,
              style: const TextStyle(color: AppColors.danger)),
        ),
      );

  Widget _contactCard() {
    final rows = <Widget>[
      _contactRow(Icons.mail_outline_rounded, 'Email', _u['email'],
          fallback: 'No email'),
      _contactRow(Icons.phone_outlined, 'Mobile', _u['mobile_no'],
          fallback: 'No mobile'),
      _contactRow(Icons.public_rounded, 'Website', _site),
    ];
    // Extra fields when present.
    void addExtra(IconData i, String label, String key) {
      if ((_u[key] ?? '').toString().isNotEmpty) {
        rows.add(_contactRow(i, label, _u[key]));
      }
    }

    addExtra(Icons.alternate_email_rounded, 'Username', 'username');
    addExtra(Icons.badge_outlined, 'User type', 'user_type');
    addExtra(Icons.location_on_outlined, 'Location', 'location');
    addExtra(Icons.wc_rounded, 'Gender', 'gender');
    addExtra(Icons.schedule_rounded, 'Time zone', 'time_zone');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Contact'),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.lg),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String label, dynamic value,
      {String fallback = '—'}) {
    final v = (value ?? '').toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 22),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(v.isEmpty ? fallback : v,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _biometricCard() {
    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: const Icon(Icons.fingerprint_rounded,
                color: AppColors.accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Biometric Lock',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground)),
                const SizedBox(height: 2),
                Text(_bioEnabled ? 'On' : 'Off',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(value: _bioEnabled, onChanged: _toggleBiometric),
        ],
      ),
    );
  }

  Widget _accountCard() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _cardTitlePadded('Account'),
          _accountRow(Icons.lock_outline_rounded, 'Change Password',
              AppColors.foreground, () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ChangePasswordScreen()));
          }),
          const Divider(height: 1, indent: AppSpacing.lg),
          _accountRow(
              Icons.logout_rounded, 'Logout', AppColors.danger, _logout),
        ],
      ),
    );
  }

  Widget _accountRow(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(icon, color: color),
      title: Text(label,
          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textMuted),
    );
  }

  Widget _cardTitle(String t) => Text(t.toUpperCase(),
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.textMuted));

  Widget _cardTitlePadded(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
        child: Align(
            alignment: Alignment.centerLeft, child: _cardTitle(t)),
      );
}
