import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

const _chartPalette = [
  AppColors.accent,
  Color(0xFF7C3AED),
  Color(0xFF059669),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
];

double _toD(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

// ───────────────────────── Number Card ─────────────────────────

/// A single metric tile (`Number Card View` item). Fetches its value lazily.
class NumberCardTile extends StatefulWidget {
  const NumberCardTile({super.key, required this.name, required this.label});
  final String name;
  final String label;

  @override
  State<NumberCardTile> createState() => _NumberCardTileState();
}

class _NumberCardTileState extends State<NumberCardTile> {
  double? _value;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await (await AppeApi.create()).numberCardValue(widget.name);
      if (mounted) {
        setState(() {
          _value = v;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  String get _display {
    final v = _value;
    if (v == null) return '—';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _loading
              ? const SizedBox(
                  height: 28,
                  width: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.4))
              : Text(_failed ? '—' : _display,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(widget.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ───────────────────────── Chart Card ─────────────────────────

/// A chart tile (`Chart View` item). Fetches the chart series + type and
/// renders a bar, line, or pie/donut chart.
class ChartCard extends StatefulWidget {
  const ChartCard({super.key, required this.name, required this.label});
  final String name;
  final String label;

  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  bool _loading = true;
  String? _error;
  String _type = 'Bar';
  List<String> _labels = [];
  List<double> _values = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = await AppeApi.create();
      final data = await api.dashboardChart(widget.name);
      _type = await api.chartType(widget.name);
      final labels = (data['labels'] as List?) ?? const [];
      final datasets = (data['datasets'] as List?) ?? const [];
      final values =
          datasets.isNotEmpty ? (datasets.first['values'] as List? ?? []) : [];
      if (mounted) {
        setState(() {
          _labels = labels.map((e) => e.toString()).toList();
          _values = values.map(_toD).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  bool get _isPie =>
      _type == 'Pie' || _type == 'Donut' || _type == 'Percentage';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground)),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 180,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? const Center(
                        child: Text('Could not load chart',
                            style: TextStyle(color: AppColors.textMuted)))
                    : _values.isEmpty
                        ? const Center(
                            child: Text('No data',
                                style:
                                    TextStyle(color: AppColors.textMuted)))
                        : _isPie
                            ? _pie()
                            : _type == 'Line'
                                ? _line()
                                : _bar(),
          ),
        ],
      ),
    );
  }

  Widget _bar() {
    final maxY = _values.fold<double>(0, (a, b) => b > a ? b : a);
    return BarChart(BarChartData(
      maxY: maxY == 0 ? 1 : maxY * 1.2,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.border, strokeWidth: 1),
      ),
      titlesData: _titles(),
      barGroups: [
        for (var i = 0; i < _values.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: _values[i],
              color: AppColors.accent,
              width: _values.length > 16 ? 4 : 10,
              borderRadius: BorderRadius.circular(3),
            ),
          ]),
      ],
    ));
  }

  Widget _line() {
    return LineChart(LineChartData(
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.border, strokeWidth: 1),
      ),
      titlesData: _titles(),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < _values.length; i++)
              FlSpot(i.toDouble(), _values[i]),
          ],
          isCurved: true,
          color: AppColors.accent,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: AppColors.accent.withValues(alpha: 0.12)),
        ),
      ],
    ));
  }

  Widget _pie() {
    final total = _values.fold<double>(0, (a, b) => a + b);
    return Row(
      children: [
        Expanded(
          child: PieChart(PieChartData(
            centerSpaceRadius: _type == 'Donut' ? 28 : 0,
            sectionsSpace: 2,
            sections: [
              for (var i = 0; i < _values.length; i++)
                PieChartSectionData(
                  value: _values[i],
                  color: _chartPalette[i % _chartPalette.length],
                  title: total == 0
                      ? ''
                      : '${(_values[i] / total * 100).round()}%',
                  radius: 60,
                  titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
            ],
          )),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _labels.length && i < _values.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _chartPalette[i % _chartPalette.length],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(_labels[i],
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  FlTitlesData _titles() {
    final step = (_labels.length / 4).ceil().clamp(1, 999);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (v, meta) => Text(
            v == v.roundToDouble() ? v.toInt().toString() : '',
            style:
                const TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          getTitlesWidget: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= _labels.length || i % step != 0) {
              return const SizedBox.shrink();
            }
            final lbl = _labels[i];
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(lbl.length > 6 ? lbl.substring(0, 5) : lbl,
                  style: const TextStyle(
                      fontSize: 8, color: AppColors.textMuted)),
            );
          },
        ),
      ),
    );
  }
}
