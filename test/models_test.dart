import 'package:flutter_test/flutter_test.dart';
import 'package:trash_monitor/models/app_settings.dart';
import 'package:trash_monitor/models/system_status.dart';
import 'package:trash_monitor/models/waste_bin.dart';
import 'package:trash_monitor/models/waste_category.dart';
import 'package:trash_monitor/models/waste_sorting.dart';

void main() {
  group('AppSettings.levelFor (threshold default 70/90)', () {
    const s = AppSettings.defaults;

    test('Normal < 70%', () {
      expect(s.levelFor(0), BinLevel.normal);
      expect(s.levelFor(69.9), BinLevel.normal);
    });

    test('Hampir penuh 70–89%', () {
      expect(s.levelFor(70), BinLevel.almostFull);
      expect(s.levelFor(89.9), BinLevel.almostFull);
    });

    test('Penuh ≥ 90%', () {
      expect(s.levelFor(90), BinLevel.full);
      expect(s.levelFor(100), BinLevel.full);
    });

    test('threshold kustom diterapkan', () {
      const custom = AppSettings(almostFullThreshold: 60, fullThreshold: 80);
      expect(custom.levelFor(65), BinLevel.almostFull);
      expect(custom.levelFor(80), BinLevel.full);
    });

    test('sanitized menjaga jarak minimum dan batas', () {
      final s1 = const AppSettings(almostFullThreshold: 95, fullThreshold: 92)
          .sanitized();
      expect(s1.fullThreshold, 92);
      expect(s1.almostFullThreshold, 87);

      final s2 =
          const AppSettings(almostFullThreshold: 10, fullThreshold: 150).sanitized();
      expect(s2.almostFullThreshold, AppSettings.minAlmostFull);
      expect(s2.fullThreshold, AppSettings.maxFull);
    });
  });

  group('Parsing data Firebase', () {
    test('WasteBin dari map RTDB (angka int, timestamp detik)', () {
      final bin = WasteBin.tryFromMap('logam', {
        'category': 'logam',
        'capacity_percentage': 78,
        'status': 'ALMOST_FULL',
        'last_updated': 1759560000, // detik
      });
      expect(bin, isNotNull);
      expect(bin!.category, WasteCategory.logam);
      expect(bin.capacityPercentage, 78.0);
      expect(bin.lastUpdated, DateTime.fromMillisecondsSinceEpoch(1759560000000));
    });

    test('kategori menerima alias bahasa Inggris dari firmware', () {
      expect(WasteCategory.tryParse('metal'), WasteCategory.logam);
      expect(WasteCategory.tryParse('Residual'), WasteCategory.anorganik);
      expect(WasteCategory.tryParse('ORGANIK'), WasteCategory.organik);
      expect(WasteCategory.tryParse('kaca'), isNull);
    });

    test('SystemStatus dari map', () {
      final s = SystemStatus.fromMap({
        'system_status': 'ON',
        'conveyor_status': 'RUNNING',
        'connection_status': 'CONNECTED',
        'last_updated': 1759560000000,
        'error': '',
      });
      expect(s.isOn, isTrue);
      expect(s.conveyorRunning, isTrue);
      expect(s.hasError, isFalse);
    });

    test('deskripsi aktivitas pemilahan', () {
      final withItem = WasteSorting(
        id: '1',
        category: WasteCategory.recyclable,
        timestamp: DateTime(2026),
        status: SortingStatus.success,
        item: 'Botol plastik',
      );
      final withoutItem = WasteSorting(
        id: '2',
        category: WasteCategory.organik,
        timestamp: DateTime(2026),
        status: SortingStatus.success,
      );
      expect(withItem.description, 'Botol plastik berhasil dipilah');
      expect(withoutItem.description, 'Sampah organik berhasil dipilah');
    });
  });
}
