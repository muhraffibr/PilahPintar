import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';

/// Push notification lokal untuk peringatan sistem (Android).
///
/// Peringatan dibuat oleh aplikasi saat mendeteksi perubahan data real-time
/// (kapasitas melewati threshold, koneksi terputus, sistem berhenti tidak
/// normal). Saat aplikasi ditutup, peringatan dibuat oleh foreground service
/// (lihat background_monitor.dart) yang memakai kelas ini juga.
class NotificationService {
  NotificationService({this.requestPermission = true});

  /// `false` di isolate foreground service (tidak ada Activity untuk dialog).
  final bool requestPermission;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// ID Android dari ID notifikasi (deterministik), sehingga peringatan yang
  /// sama dari aplikasi dan service menimpa, bukan menumpuk. Rentang
  /// 10000+ agar tidak bentrok dengan notifikasi tetap service (9001).
  static int androidIdFor(String id) => 10000 + (id.hashCode & 0x3fffffff);

  static const _channelId = 'system_alerts';
  static const _channelName = 'Peringatan sistem pemilah';
  static const _channelDescription =
      'Kapasitas tempat sampah, koneksi perangkat, dan gangguan sistem.';

  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!isSupported) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);
      if (requestPermission) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _ready = true;
    } catch (e) {
      debugPrint('Notifikasi lokal tidak tersedia: $e');
    }
  }

  Future<void> show(AppNotification notification) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: androidIdFor(notification.id),
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
        ),
      );
    } catch (e) {
      debugPrint('Gagal menampilkan notifikasi: $e');
    }
  }
}
