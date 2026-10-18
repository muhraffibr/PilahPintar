import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/waste_category.dart';
import '../../../state/monitoring_controller.dart';
import '../../../widgets/common.dart';

/// Total hari ini + jumlah per kategori (PRD §5D).
class SortingStatsCard extends StatelessWidget {
  const SortingStatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);
    final p = context.palette;
    final counts = c.todayCounts;
    final failed = c.todayFailed;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 18, color: p.inkSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Total diproses hari ini',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      theme.textTheme.labelLarge?.copyWith(color: p.inkSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(Fmt.number(c.todayTotal), style: theme.textTheme.displaySmall),
              const SizedBox(width: 8),
              Text('item', style: theme.textTheme.titleMedium?.copyWith(color: p.inkSecondary)),
            ],
          ),
          if (failed > 0)
            Text(
              '$failed item gagal dipilah (tidak dihitung)',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 4 : 2;
            final tileWidth =
                (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final category in WasteCategory.values)
                  SizedBox(
                    width: tileWidth,
                    child: _CategoryStatTile(
                      category: category,
                      count: counts[category] ?? 0,
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _CategoryStatTile extends StatelessWidget {
  const _CategoryStatTile({required this.category, required this.count});

  final WasteCategory category;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CategoryAvatar(category: category, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  Fmt.number(count),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures,
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
