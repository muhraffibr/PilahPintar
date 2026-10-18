/// Sumber data aplikasi.
///
/// * [mock] — data simulasi di memori (default, tidak butuh backend).
/// * [firebase] — Firebase Realtime Database; jalankan dengan
///   `--dart-define=DATA_SOURCE=firebase` setelah `flutterfire configure`.
enum DataSourceMode { mock, firebase }

abstract final class AppConfig {
  static const appName = 'PilahPintar';
  static const appTagline = 'Monitoring Pemilah Sampah Otomatis';
  static const appVersion = '1.0.0';
  static const buildNumber = '1';
  static const schoolName = 'SMA Negeri 1 Bandung';
  static const projectDescription =
      'Prototype akademik proyek Teknik Komputer: sistem pemilah sampah '
      'otomatis berbasis IoT untuk lingkungan sekolah.';
  static const hardwareSummary =
      'ESP32 (sensor & IoT) · STM32F411CEU6 (konveyor) · sensor ultrasonik';
  static const techSummary = 'Flutter · Firebase Realtime Database';

  static const _dataSource =
      String.fromEnvironment('DATA_SOURCE', defaultValue: 'mock');

  static DataSourceMode get dataSource => _dataSource == 'firebase'
      ? DataSourceMode.firebase
      : DataSourceMode.mock;

  /// ESP32 mengirim heartbeat tiap ±5 detik. Bila tidak ada data baru selama
  /// durasi ini (3 heartbeat terlewat), perangkat dianggap offline.
  static const deviceStaleAfter = Duration(seconds: 15);

  /// Batas waktu menunggu perangkat menjalankan perintah START/STOP.
  static const commandAckTimeout = Duration(seconds: 15);

  /// Batas waktu menulis perintah ke server.
  static const commandWriteTimeout = Duration(seconds: 10);
}
