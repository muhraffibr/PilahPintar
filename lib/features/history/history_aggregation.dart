import 'package:flutter/material.dart' show DateTimeRange;

import '../../core/utils/formatters.dart';
import '../../models/waste_category.dart';
import '../../models/waste_sorting.dart';

enum HistoryPeriod {
  today('Hari ini'),
  last7('7 hari terakhir'),
  last30('30 hari terakhir'),
  custom('Custom date');

  const HistoryPeriod(this.label);
  final String label;

  /// Rentang waktu periode; [custom] memakai [customRange] (tanggal saja).
  DateTimeRange range(DateTime now, {DateTimeRange? customRange}) {
    final today = startOfDay(now);
    return switch (this) {
      HistoryPeriod.today => DateTimeRange(start: today, end: now),
      HistoryPeriod.last7 => DateTimeRange(
          start: DateTime(today.year, today.month, today.day - 6), end: now),
      HistoryPeriod.last30 => DateTimeRange(
          start: DateTime(today.year, today.month, today.day - 29), end: now),
      HistoryPeriod.custom => _customRange(now, customRange),
    };
  }

  static DateTimeRange _customRange(DateTime now, DateTimeRange? picked) {
    if (picked == null) return DateTimeRange(start: startOfDay(now), end: now);
    final end = endOfDay(picked.end);
    return DateTimeRange(
      start: startOfDay(picked.start),
      end: end.isAfter(now) ? now : end,
    );
  }
}

enum Granularity { hour, day }

class HistoryBucket {
  HistoryBucket(this.start)
      : counts = {for (final c in WasteCategory.values) c: 0};

  final DateTime start;
  final Map<WasteCategory, int> counts;

  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// Ringkasan & deret waktu untuk grafik Riwayat.
///
/// Rentang ≤ 1 hari dikelompokkan per jam; selebihnya per hari. Hanya item
/// berhasil yang dihitung sebagai volume; item gagal dihitung terpisah.
class HistoryAggregate {
  HistoryAggregate._({
    required this.range,
    required this.granularity,
    required this.buckets,
    required this.totals,
    required this.failed,
  });

  factory HistoryAggregate.build(
    Iterable<WasteSorting> items,
    DateTimeRange range,
  ) {
    final granularity = range.end.difference(range.start) <= const Duration(days: 1)
        ? Granularity.hour
        : Granularity.day;
    final first = startOfDay(range.start);
    final buckets = <HistoryBucket>[];
    if (granularity == Granularity.hour) {
      final lastHour = isSameDay(range.end, first) ? range.end.hour : 23;
      for (var h = 0; h <= lastHour; h++) {
        buckets.add(HistoryBucket(DateTime(first.year, first.month, first.day, h)));
      }
    } else {
      final days = daysBetween(first, range.end);
      for (var d = 0; d <= days; d++) {
        buckets.add(HistoryBucket(DateTime(first.year, first.month, first.day + d)));
      }
    }

    final totals = {for (final c in WasteCategory.values) c: 0};
    var failed = 0;
    for (final s in items) {
      final t = s.timestamp;
      if (t.isBefore(range.start) || t.isAfter(range.end)) continue;
      if (!s.isSuccess) {
        failed++;
        continue;
      }
      final index = granularity == Granularity.hour
          ? (isSameDay(t, first) ? t.hour : -1)
          : daysBetween(first, t);
      if (index < 0 || index >= buckets.length) continue;
      buckets[index].counts[s.category] = buckets[index].counts[s.category]! + 1;
      totals[s.category] = totals[s.category]! + 1;
    }

    return HistoryAggregate._(
      range: range,
      granularity: granularity,
      buckets: buckets,
      totals: totals,
      failed: failed,
    );
  }

  final DateTimeRange range;
  final Granularity granularity;
  final List<HistoryBucket> buckets;
  final Map<WasteCategory, int> totals;
  final int failed;

  int get total => totals.values.fold(0, (a, b) => a + b);

  HistoryBucket? get peak {
    HistoryBucket? best;
    for (final b in buckets) {
      if (b.total > 0 && (best == null || b.total > best.total)) best = b;
    }
    return best;
  }

  String bucketLabel(HistoryBucket b) => granularity == Granularity.hour
      ? '${Fmt.time(b.start)}–${Fmt.time(b.start.add(const Duration(hours: 1)))}'
      : Fmt.dayShortYear(b.start);

  String axisLabel(HistoryBucket b) => granularity == Granularity.hour
      ? b.start.hour.toString().padLeft(2, '0')
      : Fmt.dayNumeric(b.start);
}
