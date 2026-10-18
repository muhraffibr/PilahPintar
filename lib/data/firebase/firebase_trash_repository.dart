import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../models/app_notification.dart';
import '../../models/app_settings.dart';
import '../../models/parsing.dart';
import '../../models/system_command.dart';
import '../../models/system_status.dart';
import '../../models/waste_bin.dart';
import '../../models/waste_sorting.dart';
import '../trash_repository.dart';
import 'rtdb_paths.dart';

/// Implementasi [TrashRepository] di atas Firebase Realtime Database.
///
/// Alur data: ESP32 → Firebase → aplikasi (stream `onValue`).
/// Alur kontrol: aplikasi → `commands/latest` → ESP32 → STM32.
class FirebaseTrashRepository implements TrashRepository {
  FirebaseTrashRepository(this._db) {
    _offsetSub = _db.ref(RtdbPaths.serverTimeOffsetInfo).onValue.listen((e) {
      final value = e.snapshot.value;
      if (value is num) {
        _serverTimeOffset = Duration(milliseconds: value.round());
      }
    });
  }

  final FirebaseDatabase _db;
  Duration _serverTimeOffset = Duration.zero;
  StreamSubscription<DatabaseEvent>? _offsetSub;

  @override
  String get sourceLabel => 'Firebase Realtime Database';

  @override
  bool get isSimulation => false;

  @override
  Duration get serverTimeOffset => _serverTimeOffset;

  @override
  Stream<SystemStatus?> watchSystemStatus() {
    return _db.ref(RtdbPaths.systemStatus).onValue.map((event) {
      final map = asStringMap(event.snapshot.value);
      return map == null ? null : SystemStatus.fromMap(map);
    });
  }

  @override
  Stream<List<WasteBin>> watchBins() {
    return _db.ref(RtdbPaths.bins).onValue.map((event) => [
          for (final entry in childMaps(event.snapshot.value).entries)
            ?WasteBin.tryFromMap(entry.key, entry.value),
        ]);
  }

  @override
  Stream<AppSettings> watchSettings() {
    return _db.ref(RtdbPaths.settings).onValue.map(
        (event) => AppSettings.fromMap(asStringMap(event.snapshot.value)));
  }

  @override
  Stream<List<AppNotification>> watchNotifications({int limit = 50}) {
    return _db
        .ref(RtdbPaths.notifications)
        .orderByChild('timestamp')
        .limitToLast(limit)
        .onValue
        .map((event) => [
              for (final entry in childMaps(event.snapshot.value).entries)
                ?AppNotification.tryFromMap(entry.key, entry.value),
            ]);
  }

  @override
  Stream<CommandRecord?> watchLatestCommand() {
    return _db.ref(RtdbPaths.latestCommand).onValue.map(
        (event) => CommandRecord.tryFromMap(asStringMap(event.snapshot.value)));
  }

  @override
  Stream<bool> watchBackendConnection() {
    return _db
        .ref(RtdbPaths.connectedInfo)
        .onValue
        .map((event) => event.snapshot.value == true);
  }

  @override
  Stream<List<WasteSorting>> watchSortingsSince(DateTime since) {
    return _db
        .ref(RtdbPaths.sortings)
        .orderByChild('timestamp')
        .startAt(since.millisecondsSinceEpoch)
        .onValue
        .map((event) => _parseSortings(event.snapshot.value));
  }

  @override
  Future<List<WasteSorting>> fetchSortings(DateTime from, DateTime to) async {
    final snapshot = await _db
        .ref(RtdbPaths.sortings)
        .orderByChild('timestamp')
        .startAt(from.millisecondsSinceEpoch)
        .endAt(to.millisecondsSinceEpoch)
        .get();
    return _parseSortings(snapshot.value);
  }

  List<WasteSorting> _parseSortings(Object? value) => [
        for (final entry in childMaps(value).entries)
          ?WasteSorting.tryFromMap(entry.key, entry.value),
      ];

  @override
  Future<void> sendCommand(SystemCommand command) {
    return _db.ref(RtdbPaths.latestCommand).set({
      'command': command.code,
      'issued_at': ServerValue.timestamp,
      'status': CommandStatus.pending.code,
      'source': 'mobile_app',
    });
  }

  @override
  Future<void> addNotification(AppNotification notification) async {
    // Transaksi agar entri yang sudah ada (mungkin sudah dibaca di ponsel
    // lain) tidak tertimpa.
    await _db
        .ref('${RtdbPaths.notifications}/${notification.id}')
        .runTransaction((current) => current == null
            ? Transaction.success(notification.toMap())
            : Transaction.abort());
  }

  @override
  Future<void> markNotificationRead(String id) {
    return _db.ref('${RtdbPaths.notifications}/$id/is_read').set(true);
  }

  @override
  Future<void> markAllNotificationsRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _db.ref(RtdbPaths.notifications).update({
      for (final id in ids) '$id/is_read': true,
    });
  }

  @override
  Future<void> updateSettings(AppSettings settings) {
    return _db.ref(RtdbPaths.settings).set(settings.toMap());
  }

  @override
  Future<void> dispose() async {
    await _offsetSub?.cancel();
  }
}
