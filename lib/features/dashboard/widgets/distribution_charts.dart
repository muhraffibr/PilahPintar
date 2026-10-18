import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/waste_category.dart';
import '../../../state/monitoring_controller.dart';
import '../../../widgets/charts/chart_utils.dart';
import '../../../widgets/common.dart';
import '../../../widgets/state_views.dart';

/// Donut distribusi kategori + bar chart jumlah per kategori (PRD §5E).
class DistributionCharts extends StatelessWidget {
  const DistributionCharts({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final counts = c.todayCounts;
    final total = c.todayTotal;
    final theme = Theme.of(context);

    if (total == 0) {
      return const AppCard(
        child: EmptyState(
          compact: true,
          icon: Icons.donut_large_rounded,
          title: 'Belum ada data pemilahan hari ini.',
          message: 'Grafik akan muncul setelah sistem memilah sampah.',
        ),
      );
    }

    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Komposisi kategori', style: theme.textTheme.titleSmall),
              Text('Persentase dari total item hari ini',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              _CategoryDonut(counts: counts, total: total),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Jumlah per kategori', style: theme.textTheme.titleSmall),
              Text('Item berhasil dipilah hari ini',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              SizedBox(height: 210, child: _CategoryBarChart(counts: counts)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryDonut extends StatefulWidget {
  const _CategoryDonut({required this.counts, required this.total});

  final Map<WasteCategory, int> counts;
  final int total;

  @override
  State<_CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<_CategoryDonut> {
  WasteCategory? _touched;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    final visible = [
      for (final c in WasteCategory.values)
        if ((widget.counts[c] ?? 0) > 0) c,
    ];
    final touched = _touched;
    final centerValue = touched == null ? widget.total : widget.counts[touched]!;
    final centerLabel = touched?.label ?? 'item';

    final donut = SizedBox.square(
      dimension: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final index = response?.touchedSection?.touchedSectionIndex;
                  final next = (!event.isInterestedForInteractions ||
                          index == null ||
                          index < 0 ||
                          index >= visible.length)
                      ? null
                      : visible[index];
                  if (next != _touched) setState(() => _touched = next);
                },
              ),
              sections: [
                for (final c in visible)
                  PieChartSectionData(
                    value: widget.counts[c]!.toDouble(),
                    color: p.category(c),
                    radius: c == touched ? 30 : 24,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Fmt.number(centerValue),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontFeatures: tabularFigures),
              ),
              Text(centerLabel, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );

    final legend = Column(
      children: [
        for (final c in WasteCategory.values)
          _LegendRow(
            category: c,
            count: widget.counts[c] ?? 0,
            total: widget.total,
            highlighted: c == touched,
          ),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 360) {
        return Column(
          children: [donut, const SizedBox(height: 16), legend],
        );
      }
      return Row(
        children: [
          donut,
          const SizedBox(width: 20),
          Expanded(child: legend),
        ],
      );
    });
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.category,
    required this.count,
    required this.total,
    required this.highlighted,
  });

  final WasteCategory category;
  final int count;
  final int total;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final pct = total == 0 ? 0 : count / total * 100;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted ? p.surfaceMuted : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          LegendSwatch(color: p.category(category)),
          const SizedBox(width: 10),
          Expanded(child: Text(category.label, style: theme.textTheme.bodyMedium)),
          Text(
            Fmt.number(count),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${pct.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFeatures: tabularFigures),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBarChart extends StatelessWidget {
  const _CategoryBarChart({required this.counts});

  final Map<WasteCategory, int> counts;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    final axisStyle = axisLabelStyle(context);
    final categories = WasteCategory.values;
    final maxCount =
        categories.map((c) => counts[c] ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
    final axis = niceAxis(maxCount);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: axis.max,
        barGroups: [
          for (var i = 0; i < categories.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (counts[categories[i]] ?? 0).toDouble(),
                  color: p.category(categories[i]),
                  width: 26,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: axis.interval,
          getDrawingHorizontalLine: (_) => FlLine(color: p.grid, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: p.baseline)),
        ),
        titlesData: FlTitlesData(
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
          // Label nilai langsung di atas setiap batang.
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= categories.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    Fmt.number(counts[categories[i]] ?? 0),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= categories.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    categories[i].label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: p.inkSecondary),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => p.inkPrimary,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${categories[group.x].label}\n',
              TextStyle(color: p.surface, fontWeight: FontWeight.w600),
              children: [
                TextSpan(
                  text: '${Fmt.number(rod.toY)} item',
                  style: TextStyle(color: p.surface, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
