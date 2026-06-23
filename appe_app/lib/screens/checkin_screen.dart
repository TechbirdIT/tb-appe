import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api.dart';

/// Employee check-in / check-out — the "My Day" feature.
///
/// Backed by `appe.appe_api.employee_checkin_status` (today's last record) and
/// `appe.appe_api.employee_checkin` (posts `log_type` IN/OUT + GPS). The next
/// action toggles based on the last `log_type`.
class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  static const _navy = Color(0xFF1B2440);

  AppeApi? _api;
  bool _loading = true;
  bool _busy = false;
  String? _lastType; // 'IN' | 'OUT'
  String? _lastTime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = await AppeApi.create();
      _api = api;
      final res = await api.checkinStatus();
      final data = (res is Map ? res['data'] : null);
      if (data is Map) {
        _lastType = (data['log_type'] ?? '').toString().toUpperCase();
        _lastTime = (data['time'] ?? '').toString();
      } else {
        _lastType = null; // no check-in today
        _lastTime = null;
      }
    } catch (_) {
      _lastType = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isCheckedIn => _lastType == 'IN';
  String get _nextType => _isCheckedIn ? 'OUT' : 'IN';

  Future<void> _punch() async {
    if (_api == null || _busy) return;
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition();
      } catch (_) {}
      await _api!.employeeCheckin({
        'log_type': _nextType,
        'latitude': pos?.latitude.toString() ?? '',
        'longitude': pos?.longitude.toString() ?? '',
        'latlong': pos != null ? '${pos.latitude},${pos.longitude}' : '',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checked $_nextType successfully')),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      appBar: AppBar(title: const Text('Check-in / Check-out')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isCheckedIn
                            ? Colors.green.withValues(alpha: 0.12)
                            : _navy.withValues(alpha: 0.08),
                      ),
                      child: Icon(
                        _isCheckedIn ? Icons.logout : Icons.login,
                        size: 64,
                        color: _isCheckedIn ? Colors.green : _navy,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _lastType == null
                          ? 'You have not checked in today'
                          : _isCheckedIn
                              ? 'Checked in'
                              : 'Checked out',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (_lastTime != null) ...[
                      const SizedBox(height: 6),
                      Text('Last: $_lastTime',
                          style: const TextStyle(color: Colors.black54)),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              _nextType == 'IN' ? _navy : Colors.red,
                          padding: const EdgeInsets.all(16),
                        ),
                        onPressed: _busy ? null : _punch,
                        icon: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Icon(_nextType == 'IN'
                                ? Icons.login
                                : Icons.logout),
                        label: Text('Check $_nextType'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
