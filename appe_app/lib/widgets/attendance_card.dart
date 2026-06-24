import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api.dart';
import '../theme.dart';

/// "Today's Attendance" home card — mirrors the original Appe home: shows the
/// check-in time, captured GPS location, live working hours, and a big circular
/// button to check in / out. Backed by `employee_checkin_status` /
/// `employee_checkin` (which records latitude/longitude).
class AttendanceCard extends StatefulWidget {
  const AttendanceCard({super.key});

  @override
  State<AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<AttendanceCard> {
  AppeApi? _api;
  bool _loading = true;
  bool _busy = false;
  String? _logType; // 'IN' | 'OUT' | null
  DateTime? _time;
  String? _location;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh the live working-hours readout each minute.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = await AppeApi.create();
      _api = api;
      final res = await api.checkinStatus();
      final data = (res is Map ? res['data'] : null);
      if (data is Map) {
        _logType = (data['log_type'] ?? '').toString().toUpperCase();
        _time = DateTime.tryParse((data['time'] ?? '').toString());
        _location = _coords(data);
      } else {
        _logType = null;
      }
    } catch (_) {
      _logType = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _coords(Map data) {
    final lat = data['latitude'];
    final lng = data['longitude'];
    if (lat != null && lng != null && '$lat'.isNotEmpty && '$lng'.isNotEmpty) {
      return '${_fmt(lat)}, ${_fmt(lng)}';
    }
    final ll = (data['latlong'] ?? '').toString();
    return ll.isEmpty ? null : ll;
  }

  String _fmt(dynamic v) {
    final d = double.tryParse('$v');
    return d == null ? '$v' : d.toStringAsFixed(2);
  }

  bool get _checkedIn => _logType == 'IN';
  String get _nextType => _checkedIn ? 'OUT' : 'IN';

  String get _checkInLabel {
    if (_time == null) return '--:--';
    final t = _time!;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  String get _workingHours {
    if (!_checkedIn || _time == null) return '00:00';
    final diff = DateTime.now().difference(_time!);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

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
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0284C7), AppColors.accent],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.event_available_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: AppSpacing.sm),
              const Text('Today’s Attendance',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_checkedIn ? 'Working Day' : 'Not Checked In',
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _loading
              ? const SizedBox(
                  height: 90,
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.white)))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _stat('Check In', _checkInLabel,
                              trailing: _checkedIn
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.greenAccent, size: 16)
                                  : null),
                          const SizedBox(height: AppSpacing.md),
                          _stat('Location', _location ?? '—',
                              icon: Icons.location_on_outlined),
                        ],
                      ),
                    ),
                    _punchButton(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _stat('Working Hours', _workingHours,
                              alignEnd: true),
                          const SizedBox(height: AppSpacing.md),
                          _stat('Break Time', '00:00', alignEnd: true),
                        ],
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _punchButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: PressableScale(
        onTap: _busy ? null : _punch,
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.accent),
                    )
                  : const Icon(Icons.fingerprint_rounded,
                      color: AppColors.accent, size: 40),
            ),
            const SizedBox(height: 6),
            Text(_checkedIn ? 'Tap to Check Out' : 'Tap to Check In',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value,
      {Widget? trailing, IconData? icon, bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white70, size: 13),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing,
            ],
          ],
        ),
      ],
    );
  }
}
