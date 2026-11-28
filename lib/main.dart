import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'features/auth/login_screen.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
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
      // Mode simulasi: tanpa Firebase dan tanpa login.
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
      final auth = AuthService(FirebaseAuth.instance, db);
      runApp(_AuthGate(
        auth: auth,
        // Repository & controller dibuat ulang setiap login, dan dibuang saat
        // logout, agar listener tidak berjalan tanpa izin baca.
        appBuilder: () =>
            _monitoringApp(FirebaseTrashRepository(db), notifications, auth),
      ));
  }
}

Widget _monitoringApp(TrashRepository repository,
    NotificationService notifications, [AuthService? auth]) {
  return ChangeNotifierProvider(
    create: (_) {
      final controller = MonitoringController(
        repository: repository,
        notificationService: notifications,
        auth: auth,
      )..start();
      if (auth != null) {
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

/// Mode Firebase: tampilkan login sampai operator masuk. Sesi tersimpan,
/// jadi login hanya diminta sekali sampai operator menekan Keluar.
class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.auth, required this.appBuilder});

  final AuthService auth;
  final Widget Function() appBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeModeController.instance,
            builder: (context, mode, _) => MaterialApp(
              title: AppConfig.appName,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: mode,
              locale: const Locale('id', 'ID'),
              supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: LoginScreen(auth: auth),
            ),
          );
        }
        return KeyedSubtree(key: ValueKey(user.uid), child: appBuilder());
      },
    );
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
