import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/dashboard_widgets.dart';
import 'checkin_screen.dart';
import 'leave_screen.dart';
import 'posts_screen.dart';
import 'webview_home.dart';

/// Modules — server-driven from `appe.appe_api.get_module_data`
/// (`Mobile App Module` + items). Each module is a card; Doctype/Report items
/// render as tiles, while Number Card / Chart items render as live widgets
/// (e.g. the "Insights & Reports" module).
class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  AppeApi? _api;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _modules = [];

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
      _api = api;
      final res = await api.moduleData();
      final data = (res is Map ? res['data'] : res) as List? ?? const [];
      setState(() {
        _modules =
            data.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  IconData _moduleIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('sales')) return Icons.trending_up_rounded;
    if (n.contains('field')) return Icons.place_rounded;
    if (n.contains('expense')) return Icons.receipt_long_rounded;
    if (n.contains('comm')) return Icons.forum_rounded;
    if (n.contains('insight') || n.contains('report')) {
      return Icons.insights_rounded;
    }
    return Icons.widgets_rounded;
  }

  String _monogram(String label) {
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    final w = parts.isEmpty ? '' : parts.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }

  String _ref(Map<String, dynamic> it) =>
      (it['refrence_docname'] ??
              it['report_name'] ??
              it['label'] ??
              '')
          .toString();

  void _openItem(Map<String, dynamic> it) {
    final label = (it['label'] ?? '').toString().toLowerCase();
    final doctype = (it['refrence_doctype'] ?? '').toString();
    if (label.contains('leave')) return _push(const LeaveScreen());
    if (label.contains('post') ||
        label.contains('announcement') ||
        doctype == 'Appe Post') {
      return _push(const PostsScreen());
    }
    if (label.contains('check') ||
        label.contains('attendance') ||
        doctype.contains('Check-in') ||
        doctype == 'Appe Attendance') {
      return _push(const CheckinScreen());
    }
    final site = _api?.site ?? '';
    final webUrl = (it['web_url'] ?? '').toString();
    final report = (it['report_name'] ?? '').toString();
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
        SnackBar(content: Text((it['label'] ?? 'Item').toString())),
      );
    }
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Modules')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load modules:\n$_error'))
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md),
                    children: [for (final m in _modules) _moduleCard(m)],
                  ),
                ),
    );
  }

  Widget _moduleCard(Map<String, dynamic> module) {
    final items = ((module['items'] as List?) ?? const [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .where((m) => (m['active'] ?? 1) != 0)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final name = (module['module_name'] ?? '').toString();

    final tiles = items
        .where((i) => i['type'] != 'Number Card' && i['type'] != 'Chart')
        .toList();
    final cards =
        items.where((i) => i['type'] == 'Number Card').toList();
    final charts = items.where((i) => i['type'] == 'Chart').toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(_moduleIcon(name),
                      color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground)),
              ],
            ),
            if (tiles.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.lg,
                children: [for (final it in tiles) _tile(it)],
              ),
            ],
            if (cards.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(builder: (context, c) {
                const gap = AppSpacing.md;
                final w = (c.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final it in cards)
                      SizedBox(
                        width: w,
                        child: NumberCardTile(
                            name: _ref(it),
                            label: (it['label'] ?? '').toString()),
                      ),
                  ],
                );
              }),
            ],
            for (final it in charts) ...[
              const SizedBox(height: AppSpacing.lg),
              ChartCard(name: _ref(it), label: (it['label'] ?? '').toString()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> it) {
    final label = (it['label'] ?? '').toString();
    return SizedBox(
      width: 72,
      child: PressableScale(
        onTap: () => _openItem(it),
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
