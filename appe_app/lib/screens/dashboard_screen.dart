import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/location_service.dart';
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
/// white rounded card holding circular monogram items (`Mobile App Dashboard
/// Items`, keyed off the item `label`). Tapping an item routes by its target
/// (`web_url` / `linked_doctype` / `report_name` / `screen_name`).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _bg = Color(0xFFF1F2F4);
  static const _navy = Color(0xFF1B2440);

  AppeApi? _api;
  bool _loading = true;
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
      List<Map<String, dynamic>> sections = data
          .cast<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
      // Best-effort name for the greeting header.
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
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
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
    // Route well-known items to native screens first.
    if (label.contains('leave')) {
      _push(const LeaveScreen());
      return;
    }
    if (label.contains('post') || label.contains('announcement')) {
      _push(const PostsScreen());
      return;
    }
    if (label.contains('check') || label.contains('attendance')) {
      _push(const CheckinScreen());
      return;
    }
    // Otherwise resolve the configured target.
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
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Could not load dashboard:\n$_error'),
                    ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _trackingTile(),
                  ),
                  for (final s in _sections) _sectionCard(s),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      titleSpacing: 16,
      title: Row(
        children: [
          // Tap avatar to open the profile (sign-out lives there now).
          GestureDetector(
            onTap: () => _push(const ProfileScreen()),
            child: const CircleAvatar(
              radius: 20,
              backgroundColor: Color(0xFFE3E5EA),
              child: Icon(Icons.person, color: Colors.black54),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_greeting,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey)),
              Text(_name.isEmpty ? 'Welcome' : _name,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search, color: Colors.black54)),
        // Appe Buddy sparkle
        IconButton(
          onPressed: () => _push(const AiBuddyScreen()),
          icon: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF7C4DFF)),
            ),
            child: const Icon(Icons.auto_awesome,
                size: 16, color: Color(0xFF7C4DFF)),
          ),
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
                onPressed: () => _push(const NotificationsScreen()),
                icon: const Icon(Icons.notifications_none,
                    color: Colors.black54)),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                child: const Text('2',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _trackingTile() {
    return Card(
      margin: EdgeInsets.zero,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SwitchListTile(
        secondary: const Icon(Icons.my_location, color: _navy),
        title: const Text('Live location tracking'),
        subtitle: const Text('Stores your location every 15 minutes'),
        value: false,
        onChanged: (on) =>
            on ? LocationService.start() : LocationService.stop(),
      ),
    );
  }

  Widget _sectionCard(Map<String, dynamic> s) {
    final items = ((s['items'] as List?) ?? const [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .where((m) => (m['active'] ?? 1) != 0)
        .toList();
    final hideName = (s['hide_section_name'] ?? 0) != 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideName)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text((s['section_name'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 16,
            children: [for (final it in items) _item(it)],
          ),
        ],
      ),
    );
  }

  Widget _item(Map<String, dynamic> item) {
    final label = (item['label'] ?? '').toString();
    return SizedBox(
      width: 72,
      child: InkWell(
        onTap: () => _openItem(item),
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: _navy,
              child: Text(_monogram(label),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}
