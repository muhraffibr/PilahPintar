import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'data/firebase/firebase_trash_repository.dart';
import 'data/mock/mock_trash_repository.dart';
import 'data/trash_repository.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'state/monitoring_controller.dart';
import 'widgets/state_views.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Intl.defaultLocale = 'id_ID';

  final TrashRepository repository;
  try {
    repository = await _createRepository();
  } catch (e) {
    runApp(_StartupErrorApp(error: e));
    return;
  }

  final notifications = NotificationService();
  await notifications.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => MonitoringController(
        repository: repository,
        notificationService: notifications,
      )..start(),
      child: const TrashMonitorApp(),
    ),
  );
}

Future<TrashRepository> _createRepository() async {
  switch (AppConfig.dataSource) {
    case DataSourceMode.firebase:
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final db = FirebaseDatabase.instance;
      // Cache lokal agar data terakhir tetap tampil (dengan label offline)
      // saat ponsel kehilangan koneksi. Tidak didukung di web.
      if (!kIsWeb) db.setPersistenceEnabled(true);
      return FirebaseTrashRepository(db);
    case DataSourceMode.mock:
      return MockTrashRepository.create();
  }
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
