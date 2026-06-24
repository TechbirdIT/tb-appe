import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

/// Native list of records for a DocType, via token-authed `get_list`.
/// Replaces opening the Frappe Desk in a WebView (which required a browser
/// login). Tapping a record opens a read-only detail.
class DoctypeListScreen extends StatefulWidget {
  const DoctypeListScreen({super.key, required this.doctype, this.title});

  final String doctype;
  final String? title;

  @override
  State<DoctypeListScreen> createState() => _DoctypeListScreenState();
}

const _titleKeys = [
  'title',
  'customer_name',
  'full_name',
  'fullname',
  'employee_name',
  'lead_name',
  'subject',
  'first_name',
  'name',
];
const _subtitleKeys = [
  'status',
  'email',
  'mobile_number',
  'mobile_no',
  'phone_number',
  'creation',
];

String _pick(Map<String, dynamic> r, List<String> keys, {String fallback = ''}) {
  for (final k in keys) {
    final v = r[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return fallback;
}

class _DoctypeListScreenState extends State<DoctypeListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _records = [];

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
      final rows = await api.getList(
        widget.doctype,
        fields: const ['*'],
        orderBy: 'modified desc',
        limit: 50,
      );
      setState(() {
        _records =
            rows.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title ?? widget.doctype)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.textSecondary)),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _records.isEmpty
                  ? const Center(
                      child: Text('No records',
                          style: TextStyle(color: AppColors.textMuted)))
                  : RefreshIndicator(
                      color: AppColors.accent,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm),
                        itemCount: _records.length,
                        separatorBuilder: (context, i) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (_, i) => _tile(_records[i]),
                      ),
                    ),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final title = _pick(r, _titleKeys, fallback: r['name']?.toString() ?? '—');
    final subtitle = _pick(r, _subtitleKeys);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary,
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _RecordDetail(title: title, record: r),
      )),
    );
  }
}

/// Read-only detail of a single record (all non-internal fields).
class _RecordDetail extends StatelessWidget {
  const _RecordDetail({required this.title, required this.record});
  final String title;
  final Map<String, dynamic> record;

  static const _hidden = {
    'doctype', 'owner', 'docstatus', 'idx', 'lft', 'rgt', 'parent',
    'parentfield', 'parenttype', 'modified_by', '_user_tags', '_comments',
    '_assign', '_liked_by', 'naming_series',
  };

  @override
  Widget build(BuildContext context) {
    final entries = record.entries
        .where((e) =>
            !_hidden.contains(e.key) &&
            e.value != null &&
            e.value.toString().trim().isNotEmpty &&
            e.value is! List &&
            e.value is! Map)
        .toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(_label(entries[i].key),
                              style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13)),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(entries[i].value.toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.foreground)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _label(String key) => key
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
