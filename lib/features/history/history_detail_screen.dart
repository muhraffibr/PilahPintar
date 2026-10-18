import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/waste_category.dart';
import '../../models/waste_sorting.dart';
import '../../widgets/common.dart';
import 'history_aggregation.dart';
import 'widgets/history_widgets.dart';
import 'widgets/volume_line_chart.dart';

/// Detail Riwayat satu hari: ringkasan, grafik per jam, dan semua aktivitas.
class HistoryDetailScreen extends StatelessWidget {
  const HistoryDetailScreen({super.key, required this.day, required this.items});

  final DateTime day;
  final List<WasteSorting> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final now = DateTime.now();
    final end = endOfDay(day);
    final range = DateTimeRange(start: startOfDay(day), end: end.isAfter(now) ? now : end);
    final aggregate = HistoryAggregate.build(items, range);
    final sorted = [...items]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final peak = aggregate.peak;
    final attempts = aggregate.total + aggregate.failed;
    final successRate = attempts == 0 ? null : aggregate.total / attempts * 100;
    WasteCategory? top;
    for (final c in WasteCategory.values) {
      if (top == null || aggregate.totals[c]! > aggregate.totals[top]!) top = c;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detail Riwayat'),
            Text(Fmt.dayLong(day), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ResponsiveBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HistorySummaryCard(aggregate: aggregate),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    children: [
                      InfoRow(
                        icon: Icons.schedule_rounded,
                        label: 'Jam tersibuk',
                        value: peak == null
                            ? '—'
                            : '${aggregate.bucketLabel(peak)} '
                                '(${Fmt.number(peak.total)} item)',
                      ),
                      InfoRow(
                        icon: Icons.verified_outlined,
                        label: 'Tingkat keberhasilan',
                        value: successRate == null
                            ? '—'
                            : '${Fmt.decimal(successRate, 1)}%',
                      ),
                      InfoRow(
                        icon: Icons.leaderboard_outlined,
                        label: 'Kategori terbanyak',
                        value: aggregate.total == 0 ? '—' : top?.label,
                      ),
                    ],
                  ),
                ),
                const SectionHeader(title: 'Volume per jam'),
                AppCard(
                  child: VolumeLineChart(
                    aggregate: aggregate,
                    categories: WasteCategory.values,
                  ),
                ),
                SectionHeader(
                  title: 'Semua aktivitas',
                  subtitle: '${Fmt.number(sorted.length)} catatan',
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Material(
                    color: p.surface,
                    child: Column(
                      children: [
                        for (var i = 0; i < sorted.length; i++) ...[
                          if (i > 0) const Divider(),
                          SortingRow(
                            sorting: sorted[i],
                            onTap: () => showSortingRecordSheet(context, sorted[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
