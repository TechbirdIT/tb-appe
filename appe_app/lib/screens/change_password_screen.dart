import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

/// Change the signed-in user's password via `update_password`.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscureOld = true;
  bool _obscureNew = true;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oldPwd = _old.text;
    final newPwd = _new.text;
    if (oldPwd.isEmpty || newPwd.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (newPwd.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (newPwd != _confirm.text) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = await AppeApi.create();
      await api.changePassword(oldPwd, newPwd);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully')),
        );
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not change password. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _field('Current password', _old, _obscureOld,
              () => setState(() => _obscureOld = !_obscureOld)),
          const SizedBox(height: AppSpacing.lg),
          _field('New password', _new, _obscureNew,
              () => setState(() => _obscureNew = !_obscureNew)),
          const SizedBox(height: AppSpacing.lg),
          _field('Confirm new password', _confirm, _obscureNew, null),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.danger, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Update password'),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, bool obscure,
      VoidCallback? toggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ),
        TextField(
          controller: c,
          obscureText: obscure,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: toggle == null
                ? null
                : IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: toggle,
                  ),
          ),
        ),
      ],
    );
  }
}
