import 'dart:math';

import '../../models/app_notification.dart';
import '../../models/app_settings.dart';
import '../../models/waste_bin.dart';
import '../../models/waste_category.dart';
import '../../models/waste_sorting.dart';

/// Pembangkit data prototype yang realistis untuk lingkungan sekolah:
/// aktivitas hari sekolah 06.45–15.30 dengan puncak di jam istirahat,
/// Sabtu lebih sepi, Minggu hampir kosong.
abstract final class MockDataGenerator {
  static const _categoryWeights = {
    WasteCategory.organik: 0.30,
    WasteCategory.recyclable: 0.33,
    WasteCategory.logam: 0.12,
    WasteCategory.anorganik: 0.25,
  };

  static const _items = <WasteCategory, List<(String, double)>>{
    WasteCategory.organik: [('Sisa makanan', 0.7), ('Daun', 0.3)],
    WasteCategory.recyclable: [('Botol plastik', 0.6), ('Kertas', 0.4)],
    WasteCategory.logam: [('Kaleng minuman', 1.0)],
    WasteCategory.anorganik: [
      ('Kantong kresek', 0.35),
      ('Sedotan', 0.25),
      ('Styrofoam', 0.25),
      ('Residu lainnya', 0.15),
    ],
  };

  /// Kenaikan kapasitas (%) rata-rata per item yang masuk.
  static const fillPerItem = {
    WasteCategory.organik: 0.9,
    WasteCategory.recyclable: 0.6,
    WasteCategory.logam: 0.45,
    WasteCategory.anorganik: 0.8,
  };

  /// Segmen waktu sekolah (menit sejak 00:00) beserta bobotnya.
  static const _schoolSegments = <(int, int, double)>[
    (405, 570, 0.20), // 06.45–09.30 pelajaran
    (570, 600, 0.25), // 09.30–10.00 istirahat 1
    (600, 720, 0.15), // 10.00–12.00 pelajaran
    (720, 765, 0.28), // 12.00–12.45 istirahat 2
    (765, 930, 0.12), // 12.45–15.30 pelajaran & pulang
  ];

  static T _weighted<T>(Iterable<(T, double)> options, Random rng) {
    final list = options.toList();
    final total = list.fold<double>(0, (sum, o) => sum + o.$2);
    var r = rng.nextDouble() * total;
    for (final (value, weight) in list) {
      r -= weight;
      if (r <= 0) return value;
    }
    return list.last.$1;
  }

  static WasteCategory pickCategory(Random rng) => _weighted(
      _categoryWeights.entries.map((e) => (e.key, e.value)), rng);

  static String pickItem(WasteCategory category, Random rng) =>
      _weighted(_items[category]!, rng);

  static int _sampleMinute(Random rng) {
    final (start, end, _) = _weighted(
      _schoolSegments.map((s) => (s, s.$3)),
      rng,
    );
    return start + rng.nextInt(end - start);
  }

  /// Riwayat pemilahan [days] hari ke belakang hingga [now] (urut naik).
  static List<WasteSorting> history({
    required DateTime now,
    required Random rng,
    int days = 30,
  }) {
    final out = <WasteSorting>[];
    for (var d = days - 1; d >= 0; d--) {
      final day = DateTime(now.year, now.month, now.day - d);
      final count = switch (day.weekday) {
        DateTime.saturday => 30 + rng.nextInt(25),
        DateTime.sunday => rng.nextInt(6),
        _ => 120 + rng.nextInt(50),
      };
      for (var i = 0; i < count; i++) {
        final ts = day.add(Duration(
          minutes: _sampleMinute(rng),
          seconds: rng.nextInt(60),
        ));
        final category = pickCategory(rng);
        final failed = rng.nextDouble() < 0.025;
        if (ts.isAfter(now)) continue;
        out.add(WasteSorting(
          id: 'h${ts.millisecondsSinceEpoch}_$i',
          category: category,
          timestamp: ts,
          status: failed ? SortingStatus.failed : SortingStatus.success,
          item: pickItem(category, rng),
        ));
      }
    }
    out.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return out;
  }

  /// Kondisi awal sesuai contoh PRD: 65% · 42% · 78% · 91%.
  static List<WasteBin> initialBins(DateTime now, AppSettings settings) {
    const start = {
      WasteCategory.organik: 65.0,
      WasteCategory.recyclable: 42.0,
      WasteCategory.logam: 78.0,
      WasteCategory.anorganik: 91.0,
    };
    return [
      for (final MapEntry(key: category, value: pct) in start.entries)
        WasteBin(
          id: 'bin_${category.key}',
          category: category,
          capacityPercentage: pct,
          status: settings.levelFor(pct).code,
          lastUpdated: now,
        ),
    ];
  }

  static List<AppNotification> seedNotifications(DateTime now) => [
        AppNotification(
          id: 'seed_full_anorganik',
          type: NotificationType.full,
          message: 'Tempat sampah Anorganik penuh — kapasitas 91%.',
          timestamp: now.subtract(const Duration(minutes: 4)),
          isRead: false,
          category: WasteCategory.anorganik,
        ),
        AppNotification(
          id: 'seed_almost_logam',
          type: NotificationType.almostFull,
          message: 'Tempat sampah Logam hampir penuh — kapasitas 78%.',
          timestamp: now.subtract(const Duration(minutes: 38)),
          isRead: false,
          category: WasteCategory.logam,
        ),
        AppNotification(
          id: 'seed_almost_anorganik',
          type: NotificationType.almostFull,
          message: 'Tempat sampah Anorganik hampir penuh — kapasitas 82%.',
          timestamp: now.subtract(const Duration(hours: 1, minutes: 50)),
          isRead: true,
          category: WasteCategory.anorganik,
        ),
        AppNotification(
          id: 'seed_conn_ok',
          type: NotificationType.info,
          message: 'Koneksi ke perangkat pulih.',
          timestamp: now.subtract(const Duration(hours: 20)),
          isRead: true,
        ),
        AppNotification(
          id: 'seed_conn_lost',
          type: NotificationType.connectionLost,
          message: 'Connection lost — sistem pemilah tidak mengirimkan data.',
          timestamp: now.subtract(const Duration(hours: 20, minutes: 9)),
          isRead: true,
        ),
      ];
}
