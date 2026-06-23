import 'package:flutter/material.dart';

import '../services/api.dart';

/// Leave balance — backed by `appe.appe_api.leave_balance`.
///
/// The backend returns each leave type as
/// `{type, total, used, remaining, color}` where `color` is a Flutter ARGB
/// literal like `"0xFF3B82F6"`, so we render the cards in the app's own colors.
class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  List<Map<String, dynamic>> _types = [];
  bool _loading = true;
  String? _error;

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
      final res = await api.leaveBalance();
      final data = (res is Map ? res['data'] : res) as List? ?? const [];
      setState(() {
        _types = data.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _color(dynamic raw) {
    final s = raw?.toString() ?? '0xFF6B7280';
    return Color(int.tryParse(s) ?? 0xFF6B7280);
  }

  double _num(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Balance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load leave:\n$_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _types.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(child: Text('No leave types.')),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [for (final t in _types) _leaveCard(t)],
                        ),
                ),
    );
  }

  Widget _leaveCard(Map<String, dynamic> t) {
    final color = _color(t['color']);
    final total = _num(t['total']);
    final used = _num(t['used']);
    final remaining = _num(t['remaining']);
    final pct = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text((t['type'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Text('${remaining.toStringAsFixed(0)} left',
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
                'Used ${used.toStringAsFixed(0)} of ${total.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
