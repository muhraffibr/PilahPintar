/// Struktur node Firebase Realtime Database.
///
/// ```text
/// /system_status        ← ESP32 (heartbeat ±5 dtk)
/// /bins/<kategori>      ← ESP32 (sensor ultrasonik)
/// /sortings/<pushId>    ← ESP32 (setiap item dipilah)
/// /commands/latest      ← aplikasi (START/STOP), dikonfirmasi ESP32
/// /notifications/<id>   ← aplikasi (peringatan)
/// /settings             ← aplikasi (threshold & notifikasi)
/// ```
abstract final class RtdbPaths {
  static const systemStatus = 'system_status';
  static const bins = 'bins';
  static const sortings = 'sortings';
  static const latestCommand = 'commands/latest';
  static const notifications = 'notifications';
  static const settings = 'settings';
  static const connectedInfo = '.info/connected';
  static const serverTimeOffsetInfo = '.info/serverTimeOffset';
}
