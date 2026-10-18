// Memastikan aplikasi bisa membaca data PERSIS seperti yang ditulis firmware
// ESP32 (firmware/esp32/PilahPintar_ESP32). Jika format firmware diubah,
// perbarui tes ini juga.
import 'package:flutter_test/flutter_test.dart';
import 'package:trash_monitor/models/app_settings.dart';
import 'package:trash_monitor/models/parsing.dart';
import 'package:trash_monitor/models/system_command.dart';
import 'package:trash_monitor/models/system_status.dart';
import 'package:trash_monitor/models/waste_bin.dart';
import 'package:trash_monitor/models/waste_category.dart';
import 'package:trash_monitor/models/waste_sorting.dart';

void main() {
  // Nilai {".sv":"timestamp"} sudah diganti server menjadi epoch milidetik.
  const serverTime = 1759556601000;

  test('system_status dari sendHeartbeat()', () {
    final normal = SystemStatus.fromMap(asStringMap({
      'system_status': 'ON',
      'conveyor_status': 'RUNNING',
      'connection_status': 'CONNECTED',
      'last_updated': serverTime,
      'error': '',
    })!);
    expect(normal.isOn, isTrue);
    expect(normal.conveyorRunning, isTrue);
    expect(normal.hasError, isFalse);
    expect(normal.lastUpdated, DateTime.fromMillisecondsSinceEpoch(serverTime));

    final fault = SystemStatus.fromMap(asStringMap({
      'system_status': 'ON',
      'conveyor_status': 'STOPPED',
      'connection_status': 'CONNECTED',
      'last_updated': serverTime,
      'error': 'Tombol darurat ditekan',
    })!);
    expect(fault.hasError, isTrue);
    expect(fault.errorMessage, 'Tombol darurat ditekan');
    expect(fault.conveyorRunning, isFalse);
  });

  test('bins dari reportBins() (multi-path update)', () {
    // Hasil di database setelah PATCH "organik/capacity_percentage" dst.
    final raw = {
      'organik': {
        'id': 'bin_organik',
        'category': 'organik',
        'capacity_percentage': 64.8,
        'status': 'NORMAL',
        'last_updated': serverTime,
      },
      'logam': {
        'id': 'bin_logam',
        'category': 'logam',
        'capacity_percentage': 91, // integer juga valid
        'status': 'FULL',
        'last_updated': serverTime,
      },
    };
    final bins = [
      for (final e in childMaps(raw).entries) WasteBin.tryFromMap(e.key, e.value)!,
    ];
    expect(bins.map((b) => b.category),
        containsAll([WasteCategory.organik, WasteCategory.logam]));
    final logam = bins.firstWhere((b) => b.category == WasteCategory.logam);
    expect(logam.capacityPercentage, 91.0);
    expect(AppSettings.defaults.levelFor(logam.capacityPercentage), BinLevel.full);
  });

  test('sortings dari flushSortQueue()', () {
    final ok = WasteSorting.tryFromMap('-Nx1', {
      'category': 'recyclable',
      'status': 'SUCCESS',
      'item': 'Botol plastik',
      'timestamp': serverTime,
    })!;
    expect(ok.isSuccess, isTrue);
    expect(ok.description, 'Botol plastik berhasil dipilah');

    final failedNoItem = WasteSorting.tryFromMap('-Nx2', {
      'category': 'anorganik',
      'status': 'FAILED',
      'timestamp': serverTime,
    })!;
    expect(failedNoItem.isSuccess, isFalse);
    expect(failedNoItem.item, isNull);
  });

  test('commands/latest setelah ESP32 mengubah status', () {
    for (final status in ['ACK', 'DONE', 'FAILED']) {
      final record = CommandRecord.tryFromMap({
        'command': 'STOP',
        'issued_at': serverTime,
        'status': status,
        'source': 'mobile_app',
      })!;
      expect(record.command, SystemCommand.stop);
      expect(record.status.code, status);
    }
  });
}
