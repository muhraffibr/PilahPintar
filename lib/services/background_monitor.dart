import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/firebase/firebase_trash_repository.dart';
import '../firebase_options.dart';
import '../models/waste_bin.dart';
import '../state/monitoring_controller.dart';
import 'notification_service.dart';

/// Pemantauan latar belakang (Android foreground service).
///
/// Notifikasi aplikasi dibuat di ponsel, bukan oleh server (tanpa FCM/Cloud
/// Functions, agar tetap di paket gratis Spark). Supaya peringatan tetap
/// datang saat aplikasi ditutup, foreground service menjalankan isolate Dart
/// sendiri yang berisi [MonitoringController] dengan listener Firebase
/// Realtime Database. Isolate ini tetap hidup walaupun aplikasi diusap dari
/// daftar aplikasi terbaru.
///
/// Konsekuensi: ada notifikasi tetap "PilahPintar memantau" di status bar,
/// koneksi ke Firebase terus terbuka (baterai lebih boros), dan sebagian
/// ponsel (Xiaomi/Oppo/Vivo) perlu izin "tanpa batasan baterai".
abstract final class BackgroundMonitor {
  static const _serviceId = 9001;
  static const _prefEnabled = 'background_monitor_enabled';
  static const _prefAskedBattery = 'background_monitor_asked_battery';

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Dipanggil sekali di main() sebelum runApp.
  static void init() {
    if (!isSupported) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'background_monitor',
        channelName: 'Pemantauan latar belakang',
        channelDescription:
            'Notifikasi tetap selama PilahPintar memantau tempat sampah.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Tidak perlu tugas berkala: listener RTDB yang memicu peringatan.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Pilihan pengguna di Pengaturan (bawaan: aktif).
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> isRunning() async {
    if (!isSupported) return false;
    return FlutterForegroundTask.isRunningService;
  }

  /// Menjalankan service bila diizinkan pengguna. Mengembalikan `true` bila
  /// service berjalan (aplikasi utama lalu tidak menampilkan push sendiri,
  /// agar notifikasi tidak dobel).
  static Future<bool> startIfEnabled() async {
    if (!isSupported || !await isEnabled()) return false;
    try {
      if (await FlutterForegroundTask.isRunningService) return true;
      await _askBatteryExemptionOnce();
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.specialUse],
        notificationTitle: 'PilahPintar memantau tempat sampah',
        notificationText: 'Peringatan penuh tetap dikirim saat aplikasi ditutup.',
        notificationInitialRoute: '/',
        callback: backgroundMonitorCallback,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('Foreground service gagal: ${result.error}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Foreground service gagal: $e');
      return false;
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('Gagal menghentikan foreground service: $e');
    }
  }

  /// Switch di Pengaturan. Mengembalikan status service setelah diubah.
  static Future<bool> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabled, enabled);
    } catch (_) {}
    if (enabled) return startIfEnabled();
    await stop();
    return false;
  }

  /// Minta pengecualian optimasi baterai sekali saja, agar Android tidak
  /// mematikan service. Pengguna boleh menolak.
  static Future<void> _askBatteryExemptionOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefAskedBattery) ?? false) return;
      await prefs.setBool(_prefAskedBattery, true);
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {}
  }
}

/// Titik masuk isolate service. Harus fungsi top-level.
@pragma('vm:entry-point')
void backgroundMonitorCallback() {
  FlutterForegroundTask.setTaskHandler(_MonitorTaskHandler());
}

class _MonitorTaskHandler extends TaskHandler {
  MonitoringController? _controller;
  String _lastText = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Sesi login disimpan Firebase Auth di native, jadi juga tersedia di sini
    // (termasuk setelah ponsel dinyalakan ulang). Tanpa login, rules menolak
    // semua baca, jadi service dihentikan.
    if (FirebaseAuth.instance.currentUser == null) {
      await FlutterForegroundTask.stopService();
      return;
    }

    final notifications = NotificationService(requestPermission: false);
    await notifications.init();
    final controller = MonitoringController(
      repository: FirebaseTrashRepository(FirebaseDatabase.instance),
      notificationService: notifications,
    )..start();
    controller.addListener(() => _updateServiceText(controller));
    _controller = controller;
  }

  /// Ringkasan kondisi di notifikasi tetap, mis. "Penuh: Logam".
  void _updateServiceText(MonitoringController c) {
    if (c.isLoading) return;
    final full = <String>[];
    final almost = <String>[];
    for (final level in [BinLevel.full, BinLevel.almostFull]) {
      for (final category in c.binCategoriesAt(level)) {
        (level == BinLevel.full ? full : almost).add(category.label);
      }
    }
    final String text;
    if (!c.deviceOnline) {
      text = 'Perangkat tidak mengirim data.';
    } else if (full.isNotEmpty) {
      text = 'Penuh: ${full.join(', ')}'
          '${almost.isEmpty ? '' : ' · Hampir penuh: ${almost.join(', ')}'}';
    } else if (almost.isNotEmpty) {
      text = 'Hampir penuh: ${almost.join(', ')}';
    } else {
      text = 'Semua tempat sampah normal.';
    }
    if (text == _lastText) return;
    _lastText = text;
    FlutterForegroundTask.updateService(
      notificationTitle: 'PilahPintar memantau tempat sampah',
      notificationText: text,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _controller?.dispose();
    _controller = null;
  }
}
