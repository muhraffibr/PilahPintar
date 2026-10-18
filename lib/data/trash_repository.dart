import '../models/app_notification.dart';
import '../models/app_settings.dart';
import '../models/system_command.dart';
import '../models/system_status.dart';
import '../models/waste_bin.dart';
import '../models/waste_sorting.dart';

/// Kontrak sumber data aplikasi.
///
/// Dua implementasi tersedia:
/// * `MockTrashRepository` — simulasi realistis tanpa backend.
/// * `FirebaseTrashRepository` — Firebase Realtime Database
///   (ESP32 → Firebase → aplikasi).
///
/// Semua `watch*` adalah stream real-time: UI ikut diperbarui tanpa refresh.
abstract interface class TrashRepository {
  /// Label sumber data untuk ditampilkan di UI.
  String get sourceLabel;

  /// `true` bila data berasal dari simulasi (bukan perangkat sungguhan).
  bool get isSimulation;

  /// Selisih jam server terhadap jam ponsel (untuk deteksi data basi).
  Duration get serverTimeOffset;

  /// `null` bila perangkat belum pernah mengirim status.
  Stream<SystemStatus?> watchSystemStatus();

  Stream<List<WasteBin>> watchBins();

  Stream<AppSettings> watchSettings();

  /// Notifikasi terbaru (urutan bebas; controller yang mengurutkan).
  Stream<List<AppNotification>> watchNotifications({int limit = 50});

  Stream<CommandRecord?> watchLatestCommand();

  /// Koneksi ponsel ↔ server (bukan koneksi perangkat ↔ server).
  Stream<bool> watchBackendConnection();

  /// Pemilahan sejak [since] — dipakai untuk statistik hari ini.
  Stream<List<WasteSorting>> watchSortingsSince(DateTime since);

  /// Pemilahan pada rentang [from]–[to] (inklusif) untuk halaman Riwayat.
  Future<List<WasteSorting>> fetchSortings(DateTime from, DateTime to);

  /// Menulis perintah ke `commands/latest`. Selesai ketika server menerima
  /// perintah — bukan ketika perangkat menjalankannya.
  Future<void> sendCommand(SystemCommand command);

  /// Menambah notifikasi bila ID belum ada (idempoten).
  Future<void> addNotification(AppNotification notification);

  Future<void> markNotificationRead(String id);

  Future<void> markAllNotificationsRead(List<String> ids);

  Future<void> updateSettings(AppSettings settings);

  Future<void> dispose();
}
