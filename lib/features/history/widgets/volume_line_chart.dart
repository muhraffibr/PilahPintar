import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/waste_category.dart';
import '../../../widgets/charts/chart_utils.dart';
import '../../../widgets/common.dart';
import '../history_aggregation.dart';

/// Grafik perubahan volume sampah per kategori dari waktu ke waktu.
class VolumeLineChart extends StatelessWidget {
  const VolumeLineChart({
    super.key,
    required this.aggregate,
    required this.categories,
    this.height = 220,
  });

  final HistoryAggregate aggregate;
  final List<WasteCategory> categories;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final buckets = aggregate.buckets;
    final axisStyle = axisLabelStyle(context);
    var maxValue = 0;
    for (final b in buckets) {
      for (final c in categories) {
        maxValue = math.max(maxValue, b.counts[c]!);
      }
    }
    final axis = niceAxis(maxValue);
    final labelEvery = math.max(1, (buckets.length / 6).ceil());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final c in categories)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LegendSwatch(color: p.category(c)),
                  const SizedBox(width: 6),
                  Text(c.label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(1, buckets.length - 1).toDouble(),
              minY: 0,
              maxY: axis.max,
              lineBarsData: [
                for (final c in categories)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < buckets.length; i++)
                        FlSpot(i.toDouble(), buckets[i].counts[c]!.toDouble()),
                    ],
                    color: p.category(c),
                    barWidth: 2,
                    isCurved: false,
                    dotData: FlDotData(
                      show: buckets.length <= 10,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 3.5,
                        color: p.category(c),
                        strokeWidth: 2,
                        strokeColor: p.surface,
                      ),
                    ),
                  ),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: axis.interval,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: p.grid, strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(bottom: BorderSide(color: p.baseline)),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: axis.interval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(value.toInt().toString(), style: axisStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (value != i.toDouble() ||
                          i < 0 ||
                          i >= buckets.length ||
                          i % labelEvery != 0) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(aggregate.axisLabel(buckets[i]), style: axisStyle),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => p.inkPrimary,
                  tooltipBorderRadius: BorderRadius.circular(8),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (var k = 0; k < spots.length; k++)
                      LineTooltipItem(
                        k == 0
                            ? '${aggregate.bucketLabel(buckets[spots[k].x.toInt()])}\n'
                            : '',
                        TextStyle(color: p.surface, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.left,
                        children: [
                          TextSpan(
                            text: '■ ',
                            style: TextStyle(
                                color: p.category(categories[spots[k].barIndex])),
                          ),
                          TextSpan(
                            text: '${categories[spots[k].barIndex].label}: '
                                '${spots[k].y.toInt()}',
                            style: TextStyle(
                              color: p.surface,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
