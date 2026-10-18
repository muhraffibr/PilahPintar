import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';

/// Push notification lokal untuk peringatan sistem (Android & iOS).
///
/// Peringatan dibuat oleh aplikasi saat mendeteksi perubahan data real-time
/// (kapasitas melewati threshold, koneksi terputus, sistem berhenti tidak
/// normal). Push ketika aplikasi tertutup sepenuhnya membutuhkan FCM +
/// Cloud Functions — lihat README.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 1;

  static const _channelId = 'system_alerts';
  static const _channelName = 'Peringatan sistem pemilah';
  static const _channelDescription =
      'Kapasitas tempat sampah, koneksi perangkat, dan gangguan sistem.';

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!isSupported) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(settings: settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifikasi lokal tidak tersedia: $e');
    }
  }

  Future<void> show(AppNotification notification) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: notification.type.title,
        body: notification.message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Gagal menampilkan notifikasi: $e');
    }
  }
}
