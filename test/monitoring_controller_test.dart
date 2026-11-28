import 'package:flutter_test/flutter_test.dart';
import 'package:trash_monitor/data/mock/mock_trash_repository.dart';
import 'package:trash_monitor/models/app_notification.dart';
import 'package:trash_monitor/models/system_command.dart';
import 'package:trash_monitor/models/waste_bin.dart';
import 'package:trash_monitor/models/waste_category.dart';
import 'package:trash_monitor/services/notification_service.dart';
import 'package:trash_monitor/state/monitoring_controller.dart';

Future<void> _settle([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late DateTime now;
  late MockTrashRepository repo;
  late MonitoringController controller;

  setUp(() {
    now = DateTime(2026, 10, 5, 12, 43, 21);
    repo = MockTrashRepository(
      simulate: false,
      startupDelay: Duration.zero,
      clock: () => now,
    );
    controller = MonitoringController(
      repository: repo,
      notificationService: NotificationService(),
      clock: () => now,
    )..start();
  });

  tearDown(() => controller.dispose());

  test('memuat data awal sesuai prototype PRD', () async {
    expect(controller.overallState, OverallState.loading);
    await _settle();

    expect(controller.isLoading, isFalse);
    expect(controller.deviceOnline, isTrue);
    // Bawaan saat aplikasi dibuka: sistem OFF, konveyor STOPPED.
    expect(controller.system!.isOn, isFalse);
    expect(controller.system!.conveyorRunning, isFalse);
    expect(controller.canStart, isTrue);
    expect(controller.canStop, isFalse);
    expect(controller.binFor(WasteCategory.anorganik)!.capacityPercentage, 91);
    expect(controller.levelFor(WasteCategory.anorganik), BinLevel.full);
    expect(controller.levelFor(WasteCategory.logam), BinLevel.almostFull);
    expect(controller.levelFor(WasteCategory.organik), BinLevel.normal);
    expect(controller.overallState, OverallState.systemOff);
  });

  test('melewati threshold membuat notifikasi (sekali saja)', () async {
    await _settle();
    final before = controller.notifications.length;

    repo.addCapacity(WasteCategory.recyclable, 30); // 42 → 72%
    await _settle();
    repo.addCapacity(WasteCategory.recyclable, 1); // tetap hampir penuh
    await _settle();

    final added = controller.notifications.length - before;
    expect(added, 1);
    final n = controller.notifications.first;
    expect(n.type, NotificationType.almostFull);
    expect(n.message, 'Tempat sampah Recyclable hampir penuh — kapasitas 72%.');
    expect(n.isRead, isFalse);

    now = now.add(const Duration(seconds: 5));
    repo.addCapacity(WasteCategory.recyclable, 20); // 93% → penuh
    await _settle();
    expect(controller.notifications.first.type, NotificationType.full);
  });

  test('perubahan threshold di Pengaturan langsung berlaku', () async {
    await _settle();
    expect(controller.levelFor(WasteCategory.organik), BinLevel.normal); // 65%
    await controller.updateSettings(
      controller.settings.copyWith(almostFullThreshold: 60),
    );
    await _settle();
    expect(controller.levelFor(WasteCategory.organik), BinLevel.almostFull);
  });

  test('START lalu STOP → konfirmasi perangkat → status OFF / STOPPED', () async {
    await _settle();
    final started = await controller.sendCommand(SystemCommand.start);
    expect(started.success, isTrue);
    expect(controller.system!.conveyorRunning, isTrue);
    expect(controller.canStop, isTrue);

    final outcome = await controller.sendCommand(SystemCommand.stop);

    expect(outcome.success, isTrue);
    expect(controller.system!.isOn, isFalse);
    expect(controller.system!.conveyorRunning, isFalse);
    expect(controller.overallState, OverallState.systemOff);
    expect(controller.canStart, isTrue);
    // STOP yang diminta tidak dianggap berhenti tidak normal.
    expect(
      controller.notifications.where((n) => n.type == NotificationType.abnormalStop),
      isEmpty,
    );
  });

  test('heartbeat berhenti → offline + notifikasi connection lost', () async {
    await _settle();
    repo.setDeviceOnline(false);
    now = now.add(const Duration(seconds: 20));
    await _settle(1100); // menunggu tick 1 detik controller

    expect(controller.deviceOnline, isFalse);
    expect(controller.overallState, OverallState.offline);
    expect(controller.canStart, isFalse);
    expect(controller.canStop, isFalse);
    expect(controller.notifications.first.type, NotificationType.connectionLost);
  });

  test('gangguan konveyor → state error + notifikasi', () async {
    await _settle();
    repo.simulateConveyorFault();
    await _settle();

    expect(controller.overallState, OverallState.error);
    expect(controller.notifications.first.type, NotificationType.abnormalStop);

    // START menjalankan ulang sistem dan menghapus status error.
    expect(controller.canStart, isTrue);
    final outcome = await controller.sendCommand(SystemCommand.start);
    expect(outcome.success, isTrue);
    expect(controller.system!.hasError, isFalse);
    expect(controller.system!.conveyorRunning, isTrue);
    expect(controller.overallState, isNot(OverallState.error));
  });

  test('START ditolak LOCAL_RESET menampilkan pesan reset di mesin', () async {
    await _settle();
    repo.simulateConveyorFault();
    await _settle();
    repo.startRejectReason = 'LOCAL_RESET';

    final outcome = await controller.sendCommand(SystemCommand.start);
    expect(outcome.success, isFalse);
    expect(outcome.message, startsWith('Reset tombol di mesin diperlukan'));
    expect(controller.commandPhase, CommandPhase.failed);
    expect(controller.commandError, outcome.message);
  });

  test('saat foreground service aktif, peringatan tetap dicatat & muncul di aplikasi',
      () async {
    await _settle();
    controller.pushNotifications = false; // service yang menampilkan push
    final alerts = <AppNotification>[];
    final sub = controller.alerts.listen(alerts.add);
    final before = controller.notifications.length;

    repo.addCapacity(WasteCategory.organik, 30); // 65 → 95% (penuh)
    await _settle();

    expect(alerts.single.type, NotificationType.full);
    expect(controller.notifications.length, before + 1);
    expect(controller.binCategoriesAt(BinLevel.full), contains(WasteCategory.organik));
    await sub.cancel();
  });

  test('ID notifikasi Android deterministik, tidak bentrok dengan service', () {
    final a = NotificationService.androidIdFor('FULL_logam_1759556601000');
    expect(a, NotificationService.androidIdFor('FULL_logam_1759556601000'));
    expect(a, greaterThanOrEqualTo(10000));
    expect(a, isNot(9001));
  });
}
