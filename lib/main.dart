import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'data/firebase/firebase_trash_repository.dart';
import 'data/mock/mock_trash_repository.dart';
import 'data/trash_repository.dart';
import 'firebase_options.dart';
import 'services/background_monitor.dart';
import 'services/notification_service.dart';
import 'state/monitoring_controller.dart';
import 'widgets/state_views.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Intl.defaultLocale = 'id_ID';
  await ThemeModeController.instance.load();
  BackgroundMonitor.init();

  final notifications = NotificationService();

  switch (AppConfig.dataSource) {
    case DataSourceMode.mock:
      // Mode simulasi: tanpa Firebase.
      final TrashRepository repository = await MockTrashRepository.create();
      await notifications.init();
      runApp(_monitoringApp(repository, notifications));
    case DataSourceMode.firebase:
      final FirebaseDatabase db;
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        db = FirebaseDatabase.instance;
        // Cache lokal agar data terakhir tetap tampil (dengan label offline)
        // saat ponsel kehilangan koneksi.
        db.setPersistenceEnabled(true);
      } catch (e) {
        runApp(_StartupErrorApp(error: e));
        return;
      }
      await notifications.init();
      // Aplikasi tidak memakai login: langsung membuka Dashboard.
      runApp(_monitoringApp(FirebaseTrashRepository(db), notifications,
          backgroundMonitor: true));
  }
}

Widget _monitoringApp(
  TrashRepository repository,
  NotificationService notifications, {
  bool backgroundMonitor = false,
}) {
  return ChangeNotifierProvider(
    create: (_) {
      final controller = MonitoringController(
        repository: repository,
        notificationService: notifications,
      )..start();
      if (backgroundMonitor) {
        // Mode Firebase: jalankan pemantauan latar belakang. Bila service
        // berjalan, service yang menampilkan push (agar tidak dobel).
        BackgroundMonitor.startIfEnabled().then((running) {
          controller.pushNotifications = !running;
        });
      }
      return controller;
    },
    child: const TrashMonitorApp(),
  );
}

/// Ditampilkan bila Firebase gagal diinisialisasi — aplikasi tidak diam-diam
/// beralih ke data simulasi agar tidak ada data palsu yang terlihat real-time.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Gagal terhubung ke Firebase',
              message: '$error\n\nPeriksa konfigurasi Firebase, atau jalankan '
                  'tanpa --dart-define=DATA_SOURCE=firebase untuk mode simulasi.',
            ),
          ),
        ),
      ),
    );
  }
}
