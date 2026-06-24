import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/attendance_card.dart';
import 'ai_buddy_screen.dart';
import 'checkin_screen.dart';
import 'leave_screen.dart';
import 'notifications_screen.dart';
import 'posts_screen.dart';
import 'profile_screen.dart';
import 'webview_home.dart';

/// Home dashboard after login — a faithful rebuild of the real Appe home.
///
/// The real app renders a server-driven list of sections
/// (`appe.appe_api.get_dashboard_sections` → `Mobile App Dashboard`), each a
/// card holding circular monogram items (`Mobile App Dashboard Items`, keyed
/// off the item `label`). Tapping an item routes by its target
/// (`web_url` / `linked_doctype` / `report_name` / `screen_name`).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppeApi? _api;
  bool _loading = true;
  bool _tracking = false;
  String? _error;
  List<Map<String, dynamic>> _sections = [];
  String _name = '';

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
      final res = await api.dashboardSections();
      final data = (res is Map ? res['data'] : res) as List? ?? const [];
      final sections = data
          .cast<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
      try {
        final u = await api.userDetails();
        final ud = (u is Map ? (u['data'] ?? u) : u);
        if (ud is Map) {
          _name = (ud['full_name'] ?? ud['user'] ?? ud['email'] ?? '')
              .toString();
        }
      } catch (_) {}
      setState(() {
        _sections = sections;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    if (_name.isEmpty) return 'Welcome';
    return _name.split(' ').first;
  }

  /// Monogram derived from the item label, matching the real app:
  /// 2+ words → first letter of each of the first two; 1 word → first two
  /// letters. e.g. "New Sales Order"→"NS", "Leads"→"LE", "Check-in / Check-out"→"C/".
  String _monogram(String label) {
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0].substring(0, 1) + parts[1].substring(0, 1))
          .toUpperCase();
    }
    final w = parts.isEmpty ? '' : parts.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }

  void _openItem(Map<String, dynamic> item) {
    final label = (item['label'] ?? '').toString().toLowerCase();
    if (label.contains('leave')) return _push(const LeaveScreen());
    if (label.contains('post') || label.contains('announcement')) {
      return _push(const PostsScreen());
    }
    if (label.contains('check') || label.contains('attendance')) {
      return _push(const CheckinScreen());
    }
    final site = _api?.site ?? '';
    final webUrl = (item['web_url'] ?? '').toString();
    final doctype = (item['linked_doctype'] ?? '').toString();
    final report = (item['report_name'] ?? '').toString();
    String? url;
    if (webUrl.isNotEmpty) {
      url = webUrl.startsWith('http') ? webUrl : '$site$webUrl';
    } else if (report.isNotEmpty) {
      url = '$site/app/query-report/${Uri.encodeComponent(report)}';
    } else if (doctype.isNotEmpty) {
      url = '$site/app/${doctype.toLowerCase().replaceAll(' ', '-')}';
    }
    if (url != null) {
      _push(WebViewHome(siteUrl: url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((item['label'] ?? 'Item').toString())),
      );
    }
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _header(),
              const SizedBox(height: AppSpacing.lg),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AttendanceCard(),
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg),
                child: _trackingTile(),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _errorCard()
              else
                for (final s in _sections) _sectionCard(s),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Header (navy gradient banner) ------------------------------------

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryHover],
        ),
        borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(AppSpacing.xl)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        MediaQuery.of(context).padding.top + AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xl,
      ),
      child: Row(
        children: [
          PressableScale(
            onTap: () => _push(const ProfileScreen()),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 2),
              ),
              padding: const EdgeInsets.all(2),
              child: const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_greeting,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 2),
                Text(_firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ],
            ),
          ),
          _headerIcon(Icons.search_rounded, () {}),
          _buddyButton(),
          _notificationButton(),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white),
      splashRadius: 22,
    );
  }

  Widget _buddyButton() {
    return PressableScale(
      onTap: () => _push(const AiBuddyScreen()),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
      ),
    );
  }

  Widget _notificationButton() {
    return Stack(
      alignment: Alignment.center,
      children: [
        _headerIcon(Icons.notifications_none_rounded,
            () => _push(const NotificationsScreen())),
        Positioned(
          right: 8,
          top: 10,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            constraints:
                const BoxConstraints(minWidth: 8, minHeight: 8),
          ),
        ),
      ],
    );
  }

  // ---- Tracking tile -----------------------------------------------------

  Widget _trackingTile() {
    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _tracking ? AppColors.successSoft : AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(Icons.my_location_rounded,
                color: _tracking ? AppColors.success : AppColors.accent,
                size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live location tracking',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground)),
                SizedBox(height: 2),
                Text('Updates your location every 15 min',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: _tracking,
            activeTrackColor: AppColors.success,
            onChanged: (on) {
              setState(() => _tracking = on);
              on ? LocationService.start() : LocationService.stop();
            },
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: AppCard(
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.textMuted, size: 40),
            const SizedBox(height: AppSpacing.md),
            const Text('Could not load your dashboard',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Sections ----------------------------------------------------------

  Widget _sectionCard(Map<String, dynamic> s) {
    final items = ((s['items'] as List?) ?? const [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .where((m) => (m['active'] ?? 1) != 0)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final hideName = (s['hide_section_name'] ?? 0) != 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hideName) ...[
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text((s['section_name'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.lg,
              children: [for (final it in items) _item(it)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(Map<String, dynamic> item) {
    final label = (item['label'] ?? '').toString();
    return SizedBox(
      width: 72,
      child: PressableScale(
        onTap: () => _openItem(item),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              alignment: Alignment.center,
              child: Text(_monogram(label),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: AppColors.secondary)),
          ],
        ),
      ),
    );
  }
}
