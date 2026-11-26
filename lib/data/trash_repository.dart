import '../models/app_notification.dart';
import '../models/app_settings.dart';
import '../models/system_command.dart';
import '../models/system_status.dart';
import '../models/waste_bin.dart';
import '../models/waste_sorting.dart';


abstract interface class TrashRepository {
  String get sourceLabel;
  bool get isSimulation;
  Duration get serverTimeOffset;

  Stream<SystemStatus?> watchSystemStatus();
  Stream<List<WasteBin>> watchBins();
  Stream<AppSettings> watchSettings();
  Stream<List<AppNotification>> watchNotifications({int limit = 50});
  Stream<CommandRecord?> watchLatestCommand();
  Stream<bool> watchBackendConnection();
  Stream<List<WasteSorting>> watchSortingsSince(DateTime since);

  Future<List<WasteSorting>> fetchSortings(DateTime from, DateTime to);
  Future<void> sendCommand(SystemCommand command);
  Future<void> addNotification(AppNotification notification);
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead(List<String> ids);
  Future<void> updateSettings(AppSettings settings);
  Future<void> dispose();
}
