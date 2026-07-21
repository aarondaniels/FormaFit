/// Shared fl_chart wrappers, so every chart in the app shares one set of axis,
/// grid and tooltip conventions.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../theme/tokens.dart';

/// A line chart over dated points. Renders nothing below two points, since a
/// single point has no trend to show.
class TimeSeriesChart extends StatelessWidget {
  const TimeSeriesChart({
    super.key,
    required this.points,
    required this.color,
    this.unit = '',
    this.filled = true,
  });

  final List<TimePoint> points;
  final Color color;
  final String unit;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return Center(
        child: Text(
          'Not enough data yet',
          style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
        ),
      );
    }

    // Plot against millisecond x so uneven gaps between sessions show as
    // uneven spacing rather than being evenly distributed.
    final spots = [
      for (final p in points)
        FlSpot(p.date.millisecondsSinceEpoch.toDouble(), p.value),
    ];
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final values = points.map((p) => p.value);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    // Pad the band so the line never rides the top or bottom edge; a flat
    // series still needs a non-zero range or the chart collapses.
    final pad = (maxY - minY) == 0 ? (maxY.abs() * 0.1 + 1) : (maxY - minY) * 0.15;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.cta, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                return Text(
                  compactAxisNumber(value),
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Two labels only — the ends of the range. Dated axes get
              // unreadable fast on a phone-width chart.
              interval: (maxX - minX).abs() < 1 ? null : (maxX - minX),
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  DateFormat.MMMd().format(
                    DateTime.fromMillisecondsSinceEpoch(value.toInt()),
                  ),
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.cta,
            getTooltipItems: (touched) => [
              for (final t in touched)
                LineTooltipItem(
                  '${compactAxisNumber(t.y)}$unit\n'
                  '${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(t.x.toInt()))}',
                  AppTypography.small.copyWith(color: AppColors.onDark),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2.5,
            dotData: FlDotData(
              show: spots.length <= 12,
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 3,
                color: color,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: filled,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.25),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical bars over dated buckets, for weekly volume and frequency.
class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({
    super.key,
    required this.points,
    required this.color,
    this.maxBars = 12,
  });

  final List<TimePoint> points;
  final Color color;

  /// Only the most recent [maxBars] buckets are drawn; older ones would be
  /// too narrow to read.
  final int maxBars;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          'No data yet',
          style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
        ),
      );
    }

    final shown = points.length <= maxBars
        ? points
        : points.sublist(points.length - maxBars);
    final maxY = shown.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.cta, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) =>
                  value == meta.max || value == 0
                  ? const SizedBox.shrink()
                  : Text(
                      compactAxisNumber(value),
                      style: AppTypography.small.copyWith(
                        color: AppColors.mutedOnDark,
                        fontSize: 10,
                      ),
                    ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= shown.length) return const SizedBox.shrink();
                // Label every other bucket so the axis stays legible.
                if (shown.length > 6 && i.isOdd) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    DateFormat.Md().format(shown[i].date),
                    style: AppTypography.small.copyWith(
                      color: AppColors.mutedOnDark,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.cta,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${compactAxisNumber(rod.toY)}\n'
              'week of ${DateFormat.MMMd().format(shown[group.x].date)}',
              AppTypography.small.copyWith(color: AppColors.onDark),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < shown.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: shown[i].value,
                  color: color,
                  width: 12,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Share-of-total breakdown, used for volume per muscle group.
class MuscleGroupDonut extends StatelessWidget {
  const MuscleGroupDonut({super.key, required this.volumeByGroup});

  final Map<String, double> volumeByGroup;

  @override
  Widget build(BuildContext context) {
    final entries = volumeByGroup.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No volume logged yet',
          style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
        ),
      );
    }

    final total = entries.fold(0.0, (sum, e) => sum + e.value);

    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: [
                for (final e in entries)
                  PieChartSectionData(
                    value: e.value,
                    color: AppColors.forMuscleGroup(e.key),
                    radius: 26,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in entries.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.forMuscleGroup(e.key),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          e.key,
                          style: AppTypography.small.copyWith(
                            color: AppColors.onDark,
                          ),
                        ),
                      ),
                      Text(
                        '${(e.value / total * 100).round()}%',
                        style: AppTypography.small.copyWith(
                          color: AppColors.mutedOnDark,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Axis-friendly number: thousands as "12k", otherwise a plain integer.
String compactAxisNumber(double value) {
  if (value.abs() >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  if (value.abs() < 10 && value != value.roundToDouble()) {
    return value.toStringAsFixed(1);
  }
  return value.round().toString();
}
