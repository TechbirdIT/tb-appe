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
/// employees. Mirrors the original Appe screen: a live map of the employee's
/// location, a greeting + employee ID, a running working-hours timer, and a
/// large check-in/out button, plus "Go to Home" and "Logout".
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
    // If checked in, keep posting live location while this screen is open.
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

  String get _greeting {
    final h = DateTime.now().hour;
    final part = h < 12
        ? 'Good Morning'
        : h < 17
            ? 'Good Afternoon'
            : h < 21
                ? 'Good Evening'
                : 'Good Night';
    return _empName.isEmpty ? part : '$part, $_empName';
  }

  String get _timer {
    if (!_checkedIn || _checkInTime == null) return '00:00:00';
    final d = DateTime.now().difference(_checkInTime!);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  String get _nowStr {
    final n = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.day} ${months[n.month - 1]} ${n.year} ${two(n.hour)}:${two(n.minute)}';
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
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  _map(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        children: [
                          Text(_greeting,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.foreground)),
                          if (_empId.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('ID: $_empId',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Text(_timer,
                              style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: AppColors.foreground)),
                          const SizedBox(height: 4),
                          Text(_nowStr,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: AppSpacing.xl),
                          _punchButton(),
                          const SizedBox(height: AppSpacing.xl),
                          _bigButton('Go to Home', AppColors.success,
                              () => Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const DashboardScreen()),
                                  )),
                          const SizedBox(height: AppSpacing.md),
                          _bigButton('Logout', AppColors.danger, _logout),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _map() {
    final center = _here ?? const LatLng(0, 0);
    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          FlutterMap(
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
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_pin,
                        color: AppColors.danger, size: 44),
                  ),
                ]),
            ],
          ),
          if (_here == null)
            const Center(
                child: Text('Locating…',
                    style: TextStyle(color: AppColors.textSecondary))),
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              onPressed: _locate,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _punchButton() {
    return PressableScale(
      onTap: _busy ? null : _punch,
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFD32F2F), Color(0xFF7B1FA2), Color(0xFF1A237E)],
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 10)),
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
                    color: Colors.white, size: 56),
            const SizedBox(height: 8),
            Text('Check-$_nextType',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _bigButton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: color, minimumSize: const Size.fromHeight(52)),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
