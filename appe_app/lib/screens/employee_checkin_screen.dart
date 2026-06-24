import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/api.dart';
import '../services/location_service.dart';
import '../theme.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Full-screen employee check-in / check-out shown right after login for
/// employees: an immersive map of the employee's location, a floating
/// working-hours card, and an animated check-in/out control.
class EmployeeCheckinScreen extends StatefulWidget {
  const EmployeeCheckinScreen({super.key});

  @override
  State<EmployeeCheckinScreen> createState() =>
      _EmployeeCheckinScreenState();
}

class _EmployeeCheckinScreenState extends State<EmployeeCheckinScreen> {
  final _mapController = MapController();
  AppeApi? _api;
  bool _loading = true;
  bool _busy = false;

  String _empName = '';
  String _empId = '';
  String? _logType; // 'IN' | 'OUT' | null
  DateTime? _checkInTime;
  LatLng? _here;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _checkedIn) setState(() {});
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
      final emp = await api.employeeDetails();
      final ed = (emp is Map ? (emp['data'] ?? emp) : emp);
      if (ed is Map) {
        _empName = (ed['employee_name'] ?? '').toString();
        _empId = (ed['name'] ?? '').toString();
      }
      final status = await api.checkinStatus();
      final sd = (status is Map ? status['data'] : null);
      if (sd is Map) {
        _logType = (sd['log_type'] ?? '').toString().toUpperCase();
        _checkInTime = DateTime.tryParse((sd['time'] ?? '').toString());
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    _locate();
    if (_checkedIn) LocationService.start();
  }

  Future<void> _locate() async {
    try {
      if (!await LocationService.ensurePermission()) return;
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _here = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_here!, 16);
    } catch (_) {}
  }

  bool get _checkedIn => _logType == 'IN';
  String get _nextType => _checkedIn ? 'OUT' : 'IN';

  String get _firstGreeting {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : h < 21
                ? 'Good evening'
                : 'Good night';
  }

  String get _timer {
    if (!_checkedIn || _checkInTime == null) return '00:00:00';
    final d = DateTime.now().difference(_checkInTime!);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  String get _checkInLabel {
    final t = _checkInTime;
    if (t == null) return '—';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  String get _locationLabel {
    final p = _here;
    if (p == null) return 'Locating…';
    return '${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)}';
  }

  String get _nowStr {
    final n = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.day} ${months[n.month - 1]} ${n.year} · ${two(n.hour)}:${two(n.minute)}';
  }

  Future<void> _punch() async {
    if (_api == null || _busy) return;
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        if (await LocationService.ensurePermission()) {
          pos = await Geolocator.getCurrentPosition();
        }
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
      if (_nextType == 'IN') {
        LocationService.start();
      } else {
        LocationService.stop();
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

  Future<void> _logout() async {
    await LocationService.stop();
    await AppeApi.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _mapHeader(),
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Column(
                    children: [
                      _heroCard(),
                      const SizedBox(height: AppSpacing.xl),
                      _PulseRing(
                        active: _checkedIn,
                        color: _checkedIn
                            ? AppColors.success
                            : AppColors.accent,
                        size: 168,
                        child: _punchButton(),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () =>
                                    Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const DashboardScreen()),
                                ),
                                icon: const Icon(Icons.home_rounded),
                                label: const Text('Go to Home'),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextButton.icon(
                              onPressed: _logout,
                              style: TextButton.styleFrom(
                                  foregroundColor: AppColors.danger),
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Logout'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ── Map header with overlaid greeting + status ──────────────────────────

  Widget _mapHeader() {
    final center = _here ?? const LatLng(0, 0);
    return SizedBox(
      height: 320,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(28)),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: _here == null ? 2 : 16,
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.kameshkumar.appe.replica',
                  maxNativeZoom: 19,
                ),
                if (_here != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _here!,
                      width: 60,
                      height: 60,
                      alignment: Alignment.topCenter,
                      child: _locationMarker(),
                    ),
                  ]),
              ],
            ),
          ),
          // Top scrim so the greeting reads over any map.
          Container(
            height: 150,
            decoration: const BoxDecoration(
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(28)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC0F172A), Color(0x000F172A)],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 2),
                    ),
                    child: const CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_firstGreeting,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        Text(_empName.isEmpty ? 'Welcome' : _empName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(
                                      color: Colors.black38, blurRadius: 4)
                                ])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Status chip + recenter.
          Positioned(
            left: AppSpacing.lg,
            bottom: AppSpacing.xl + 8,
            child: _statusChip(),
          ),
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.xl + 8,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 3,
              onPressed: _locate,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.danger,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)
            ],
          ),
          child: const Icon(Icons.person_pin_circle,
              color: Colors.white, size: 18),
        ),
      ],
    );
  }

  Widget _statusChip() {
    final on = _checkedIn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: on ? AppColors.success : AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(on ? 'On the clock' : 'Off duty',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground)),
        ],
      ),
    );
  }

  // ── Floating hero card (timer + stats) ──────────────────────────────────

  Widget _heroCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('WORKING HOURS',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted)),
                    if (_checkedIn) ...[
                      const SizedBox(width: 6),
                      const _BlinkDot(),
                    ],
                  ],
                ),
                if (_empId.isNotEmpty)
                  Text(_empId,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(_timer,
                style: const TextStyle(
                    fontSize: 46,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppColors.foreground)),
            const SizedBox(height: 2),
            Text(_nowStr,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Expanded(
                  child: _miniStat(Icons.login_rounded, 'Check-in',
                      _checkedIn ? _checkInLabel : '—'),
                ),
                Container(width: 1, height: 34, color: AppColors.border),
                Expanded(
                  child: _miniStat(Icons.location_on_outlined, 'Location',
                      _locationLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: AppColors.accent, size: 20),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground)),
      ],
    );
  }

  // ── Big check button ────────────────────────────────────────────────────

  Widget _punchButton() {
    return PressableScale(
      onTap: _busy ? null : _punch,
      child: Container(
        width: 168,
        height: 168,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE11D48), Color(0xFF7C3AED), Color(0xFF1E3A8A)],
          ),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 12)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _busy
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3))
                : const Icon(Icons.fingerprint_rounded,
                    color: Colors.white, size: 54),
            const SizedBox(height: 6),
            Text(_checkedIn ? 'Check OUT' : 'Check IN',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

/// Expanding pulse rings around a child (used on the active check button).
class _PulseRing extends StatefulWidget {
  const _PulseRing({
    required this.active,
    required this.color,
    required this.size,
    required this.child,
  });
  final bool active;
  final Color color;
  final double size;
  final Widget child;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size + 60,
      height: widget.size + 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.active)
            for (final phase in [0.0, 0.5])
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = (_c.value + phase) % 1.0;
                  return Container(
                    width: widget.size * (1 + t * 0.34),
                    height: widget.size * (1 + t * 0.34),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.color.withValues(alpha: (1 - t) * 0.45),
                        width: 2.5,
                      ),
                    ),
                  );
                },
              ),
          widget.child,
        ],
      ),
    );
  }
}

/// A softly blinking dot, indicating an active session.
class _BlinkDot extends StatefulWidget {
  const _BlinkDot();
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: AppColors.success, shape: BoxShape.circle),
      ),
    );
  }
}
