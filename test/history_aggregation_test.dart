import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trash_monitor/features/history/history_aggregation.dart';
import 'package:trash_monitor/models/waste_category.dart';
import 'package:trash_monitor/models/waste_sorting.dart';

WasteSorting _s(DateTime t, WasteCategory c, {bool ok = true}) => WasteSorting(
      id: '${t.millisecondsSinceEpoch}_${c.key}',
      category: c,
      timestamp: t,
      status: ok ? SortingStatus.success : SortingStatus.failed,
    );

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('rentang satu hari dikelompokkan per jam', () {
    final day = DateTime(2026, 10, 5);
    final items = [
      _s(day.add(const Duration(hours: 9, minutes: 40)), WasteCategory.organik),
      _s(day.add(const Duration(hours: 9, minutes: 50)), WasteCategory.logam),
      _s(day.add(const Duration(hours: 12, minutes: 5)), WasteCategory.organik),
      _s(day.add(const Duration(hours: 12, minutes: 6)), WasteCategory.organik,
          ok: false),
    ];
    final agg = HistoryAggregate.build(
      items,
      DateTimeRange(start: day, end: day.add(const Duration(hours: 23, minutes: 59))),
    );

    expect(agg.granularity, Granularity.hour);
    expect(agg.buckets.length, 24);
    expect(agg.total, 3);
    expect(agg.failed, 1);
    expect(agg.totals[WasteCategory.organik], 2);
    expect(agg.buckets[9].total, 2);
    expect(agg.buckets[12].total, 1);
    expect(agg.peak!.start.hour, 9);
  });

  test('periode 7 hari dikelompokkan per hari', () {
    final now = DateTime(2026, 10, 5, 14);
    final range = HistoryPeriod.last7.range(now);
    final items = [
      _s(DateTime(2026, 9, 29, 10), WasteCategory.recyclable),
      _s(DateTime(2026, 10, 5, 10), WasteCategory.anorganik),
      _s(DateTime(2026, 9, 28, 10), WasteCategory.anorganik), // di luar rentang
    ];
    final agg = HistoryAggregate.build(items, range);

    expect(agg.granularity, Granularity.day);
    expect(agg.buckets.length, 7);
    expect(agg.buckets.first.start, DateTime(2026, 9, 29));
    expect(agg.total, 2);
    expect(agg.buckets.last.counts[WasteCategory.anorganik], 1);
  });

  test('hari ini hanya sampai jam berjalan', () {
    final now = DateTime(2026, 10, 5, 13, 20);
    final agg = HistoryAggregate.build(const [], HistoryPeriod.today.range(now));
    expect(agg.buckets.length, 14); // 00..13
    expect(agg.total, 0);
  });
}
