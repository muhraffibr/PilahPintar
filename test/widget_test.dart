import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:trash_monitor/app.dart';
import 'package:trash_monitor/data/mock/mock_trash_repository.dart';
import 'package:trash_monitor/services/notification_service.dart';
import 'package:trash_monitor/state/monitoring_controller.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340); // 360 × 780 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MonitoringController(
          repository: MockTrashRepository(
            simulate: false,
            startupDelay: const Duration(milliseconds: 300),
          ),
          notificationService: NotificationService(),
        )..start(),
        child: const TrashMonitorApp(),
      ),
    );
  }

  testWidgets('aplikasi langsung membuka Dashboard tanpa login', (tester) async {
    await pumpApp(tester);

    // State loading tampil lebih dulu.
    expect(find.text('Mengambil data dari sistem…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('System Status'), findsOneWidget);
    expect(find.text('ONLINE'), findsOneWidget);
    for (final label in ['Organik', 'Recyclable', 'Logam', 'Anorganik']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('91%'), findsOneWidget);

    // Tidak ada autentikasi.
    for (final text in ['Login', 'Sign up', 'Password', 'Logout']) {
      expect(find.textContaining(text), findsNothing);
    }

    // Kontrol sistem tersedia.
    await tester.ensureVisible(find.text('STOP SYSTEM'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('START SYSTEM'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('STOP menampilkan dialog konfirmasi', (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    await tester.ensureVisible(find.text('STOP SYSTEM'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('STOP SYSTEM'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Hentikan sistem?'), findsOneWidget);
    expect(
      find.textContaining('Apakah Anda yakin ingin menghentikan sistem?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Batal'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigasi ke Riwayat dan Pengaturan', (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Riwayat').last);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Hari ini'), findsOneWidget);
    expect(find.text('7 hari terakhir'), findsOneWidget);
    expect(find.text('30 hari terakhir'), findsOneWidget);

    await tester.tap(find.text('Pengaturan').last);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Notification Settings'), findsOneWidget);
    expect(find.text('Almost Full Threshold'), findsOneWidget);
    expect(find.text('Full Threshold'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
