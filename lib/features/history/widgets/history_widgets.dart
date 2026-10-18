import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/waste_category.dart';
import '../../../models/waste_sorting.dart';
import '../../../widgets/common.dart';
import '../history_aggregation.dart';

/// Ringkasan total & per kategori — sekaligus menjadi "tampilan tabel"
/// dari grafik.
class HistorySummaryCard extends StatelessWidget {
  const HistorySummaryCard({super.key, required this.aggregate, this.caption});

  final HistoryAggregate aggregate;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final total = aggregate.total;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total sampah',
              style: theme.textTheme.labelLarge?.copyWith(color: p.inkSecondary)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(Fmt.number(total), style: theme.textTheme.displaySmall),
              const SizedBox(width: 8),
              Text('item',
                  style: theme.textTheme.titleMedium?.copyWith(color: p.inkSecondary)),
            ],
          ),
          if (caption != null) Text(caption!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          const Divider(),
          for (final c in WasteCategory.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  CategoryAvatar(category: c, size: 28),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.label, style: theme.textTheme.bodyMedium)),
                  Text(
                    '${Fmt.number(aggregate.totals[c] ?? 0)} item',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      total == 0
                          ? '–'
                          : '${((aggregate.totals[c] ?? 0) / total * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFeatures: tabularFigures),
                    ),
                  ),
                ],
              ),
            ),
          if (aggregate.failed > 0) ...[
            const Divider(),
            const SizedBox(height: 8),
            Text(
              '${Fmt.number(aggregate.failed)} item gagal dipilah (tidak termasuk total).',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Baris "13:20 | Organik | Berhasil".
class SortingRow extends StatelessWidget {
  const SortingRow({super.key, required this.sorting, this.onTap});

  final WasteSorting sorting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final ok = sorting.isSuccess;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                Fmt.time(sorting.timestamp),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            Container(width: 1, height: 18, color: p.grid),
            const SizedBox(width: 12),
            LegendSwatch(color: p.category(sorting.category)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sorting.category.label, style: theme.textTheme.bodyMedium),
                  if (sorting.item != null)
                    Text(sorting.item!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 16,
              color: ok ? StatusColors.good : StatusColors.critical,
            ),
            const SizedBox(width: 4),
            Text(sorting.status.label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Detail satu kejadian pemilahan.
Future<void> showSortingRecordSheet(BuildContext context, WasteSorting s) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryAvatar(category: s.category, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.description, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              InfoRow(label: 'Waktu', value: Fmt.full(s.timestamp)),
              InfoRow(label: 'Kategori', value: s.category.label),
              InfoRow(label: 'Jenis sampah', value: s.item ?? 'Tidak terdeteksi'),
              InfoRow(
                label: 'Status',
                valueWidget: StatusPill(
                  label: s.status.label,
                  tone: s.isSuccess ? StatusTone.good : StatusTone.critical,
                ),
              ),
              InfoRow(
                label: 'Tujuan',
                value: s.isSuccess
                    ? 'Tempat sampah ${s.category.label}'
                    : 'Tidak masuk tempat sampah',
              ),
              InfoRow(label: 'ID', value: s.id),
            ],
          ),
        ),
      );
    },
  );
}

/// Elemen daftar riwayat: header hari atau satu baris pemilahan.
sealed class HistoryListItem {
  const HistoryListItem();
}

class DayHeaderItem extends HistoryListItem {
  const DayHeaderItem(this.day, this.items);
  final DateTime day;
  final List<WasteSorting> items;
}

class SortingItem extends HistoryListItem {
  const SortingItem(this.sorting);
  final WasteSorting sorting;
}

/// Mengelompokkan [sortedDesc] per hari dan memotong pada [limit] baris.
List<HistoryListItem> buildHistoryList(List<WasteSorting> sortedDesc, int limit) {
  final byDay = <DateTime, List<WasteSorting>>{};
  for (final s in sortedDesc) {
    byDay.putIfAbsent(startOfDay(s.timestamp), () => []).add(s);
  }
  final out = <HistoryListItem>[];
  var rows = 0;
  for (final entry in byDay.entries) {
    if (rows >= limit) break;
    out.add(DayHeaderItem(entry.key, entry.value));
    for (final s in entry.value) {
      if (rows >= limit) break;
      out.add(SortingItem(s));
      rows++;
    }
  }
  return out;
}

class DayHeaderTile extends StatelessWidget {
  const DayHeaderTile({super.key, required this.item, required this.onTap});

  final DayHeaderItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final success = item.items.where((s) => s.isSuccess).length;
    return Material(
      color: p.surfaceMuted,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(Fmt.dayLong(item.day), style: theme.textTheme.titleSmall),
              ),
              Text('${Fmt.number(success)} item', style: theme.textTheme.bodySmall),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, color: p.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
