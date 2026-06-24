import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

/// Native report viewer — runs a Frappe report via `query_report.run` with the
/// API token and renders the rows in a table. Avoids the WebView/Desk login
/// entirely (the original Appe app renders reports natively this way).
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.reportName, this.title});

  final String reportName;
  final String? title;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _Col {
  _Col(this.label, this.fieldname, this.fieldtype);
  String label;
  final String fieldname;
  final String fieldtype;
  _Style? style;
}

/// Per-column presentation from `Appe Report Column`.
class _Style {
  _Style({this.color, this.bold = false, this.fontSize = 13, this.align});
  final Color? color;
  final bool bold;
  final double fontSize;
  final TextAlign? align;
}

class _ReportScreenState extends State<ReportScreen> {
  bool _loading = true;
  String? _error;
  List<_Col> _cols = [];
  List<List<String>> _rows = [];

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
      final data = await api.runReport(widget.reportName);
      final cols = _parseColumns((data['columns'] as List?) ?? const []);
      await _applyStyling(api, cols); // Appe Report Column overrides
      final result = (data['result'] as List?) ?? const [];
      setState(() {
        _cols = cols;
        _rows = result
            .where((r) => r != null)
            .map((r) => _rowToCells(r, cols))
            .toList();
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

  /// Pulls per-column styling from the `Appe Report` doc (the report name is
  /// also the Appe Report name) and attaches it to matching columns.
  Future<void> _applyStyling(AppeApi api, List<_Col> cols) async {
    try {
      final doc = await api.getDoc('Appe Report', widget.reportName);
      final styled = (doc['column'] as List?) ?? const [];
      if (styled.isEmpty) return;
      final byField = {for (final c in cols) c.fieldname: c};
      for (final raw in styled.cast<Map>()) {
        final s = raw.cast<String, dynamic>();
        final col = byField[(s['column_fieldname'] ?? '').toString()];
        if (col == null) continue;
        final label = (s['column_label'] ?? '').toString();
        if (label.isNotEmpty) col.label = label;
        col.style = _Style(
          color: _parseColor((s['color'] ?? '').toString()),
          bold: (s['is_bold'] ?? 0) != 0,
          fontSize: _fontSize((s['font_size'] ?? '').toString()),
          align: _align((s['position'] ?? '').toString()),
        );
      }
    } catch (_) {
      // Report has no Appe Report styling — keep the defaults.
    }
  }

  double _fontSize(String s) => switch (s) {
        'Small' => 11,
        'Large' => 16,
        _ => 13,
      };

  TextAlign? _align(String s) => switch (s) {
        'Right' => TextAlign.right,
        'Center' => TextAlign.center,
        'Left' => TextAlign.left,
        _ => null,
      };

  Color? _parseColor(String hex) {
    var h = hex.trim().replaceFirst('#', '');
    if (h.isEmpty) return null;
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  List<_Col> _parseColumns(List raw) {
    final out = <_Col>[];
    for (final c in raw) {
      if (c is Map) {
        out.add(_Col(
          (c['label'] ?? c['fieldname'] ?? '').toString(),
          (c['fieldname'] ?? c['label'] ?? '').toString(),
          (c['fieldtype'] ?? 'Data').toString(),
        ));
      } else if (c is String) {
        // "Label:Fieldtype:Width" form.
        final parts = c.split(':');
        out.add(_Col(parts.isNotEmpty ? parts[0] : c, parts.isNotEmpty ? parts[0] : c,
            parts.length > 1 ? parts[1] : 'Data'));
      }
    }
    return out;
  }

  List<String> _rowToCells(dynamic row, List<_Col> cols) {
    String fmt(dynamic v) {
      if (v == null) return '';
      return v.toString();
    }

    if (row is Map) {
      return cols.map((c) => fmt(row[c.fieldname])).toList();
    }
    if (row is List) {
      return [
        for (var i = 0; i < cols.length; i++)
          i < row.length ? fmt(row[i]) : '',
      ];
    }
    return [fmt(row)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title ?? widget.reportName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorState()
              : _rows.isEmpty
                  ? const Center(
                      child: Text('No records',
                          style: TextStyle(color: AppColors.textMuted)))
                  : _table(),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
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

  TextStyle _cellStyle(_Style? s) => TextStyle(
        color: s?.color ?? AppColors.textSecondary,
        fontSize: s?.fontSize ?? 13,
        fontWeight: (s?.bold ?? false) ? FontWeight.w700 : FontWeight.normal,
      );

  Widget _table() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: Text('${_rows.length} record${_rows.length == 1 ? '' : 's'}',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(AppColors.muted),
                headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                    fontSize: 13),
                dataTextStyle: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
                columns: [
                  for (final c in _cols)
                    DataColumn(
                      label: Text(c.label,
                          textAlign: c.style?.align ?? TextAlign.start),
                    ),
                ],
                rows: [
                  for (final row in _rows)
                    DataRow(cells: [
                      for (var i = 0; i < _cols.length; i++)
                        DataCell(ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 220),
                          child: Text(
                            i < row.length ? row[i] : '',
                            overflow: TextOverflow.ellipsis,
                            textAlign:
                                _cols[i].style?.align ?? TextAlign.start,
                            style: _cellStyle(_cols[i].style),
                          ),
                        )),
                    ]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
