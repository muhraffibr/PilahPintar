import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../core/utils/formatters.dart';
import '../data/trash_repository.dart';
import '../models/app_notification.dart';
import '../models/app_settings.dart';
import '../models/system_command.dart';
import '../models/system_status.dart';
import '../models/waste_bin.dart';
import '../models/waste_category.dart';
import '../models/waste_sorting.dart';
import '../services/notification_service.dart';

/// Kondisi keseluruhan aplikasi (PRD §13).
enum OverallState {
  loading,
  waitingDevice,
  online,
  warning,
  full,
  systemOff,
  offline,
  error,
}

enum OfflineReason { phoneOffline, deviceSilent }

enum CommandPhase { idle, sending, awaitingDevice, failed }

enum ActivityKind { sorted, sortFailed, almostFull, full, connection, error, info }

class ActivityEntry {
  const ActivityEntry({
    required this.time,
    required this.message,
    required this.kind,
    this.category,
  });

  factory ActivityEntry.fromSorting(WasteSorting s) => ActivityEntry(
        time: s.timestamp,
        message: s.description,
        kind: s.isSuccess ? ActivityKind.sorted : ActivityKind.sortFailed,
        category: s.category,
      );

  factory ActivityEntry.fromNotification(AppNotification n) => ActivityEntry(
        time: n.timestamp,
        message: n.message,
        kind: switch (n.type) {
          NotificationType.almostFull => ActivityKind.almostFull,
          NotificationType.full => ActivityKind.full,
          NotificationType.connectionLost => ActivityKind.connection,
          NotificationType.abnormalStop => ActivityKind.error,
          NotificationType.info => ActivityKind.info,
        },
        category: n.category,
      );

  final DateTime time;
  final String message;
  final ActivityKind kind;
  final WasteCategory? category;
}

class CommandOutcome {
  const CommandOutcome(this.success, this.message);
  final bool success;
  final String message;
}

/// Satu-satunya sumber state untuk UI.
///
/// Mendengarkan stream real-time dari [TrashRepository], menghitung status
/// turunan (online/offline, level kapasitas, statistik), mendeteksi kejadian
/// yang perlu dinotifikasi, dan mengirim perintah START/STOP.
class MonitoringController extends ChangeNotifier {
  MonitoringController({
    required this.repository,
    required this.notificationService,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        _todayStart = startOfDay((clock ?? DateTime.now)());

  final TrashRepository repository;
  final NotificationService notificationService;
  final DateTime Function() _clock;

  final List<StreamSubscription<dynamic>> _subs = [];
  StreamSubscription<List<WasteSorting>>? _todaySub;
  Timer? _ticker;
  final _alerts = StreamController<AppNotification>.broadcast();
  bool _disposed = false;

  SystemStatus? _system;
  bool _systemLoaded = false;
  Map<WasteCategory, WasteBin> _bins = const {};
  bool _binsLoaded = false;
  AppSettings _settings = AppSettings.defaults;
  bool _settingsLoaded = false;
  List<WasteSorting> _today = const [];
  List<AppNotification> _notifications = const [];
  CommandRecord? _latestCommand;
  bool _backendConnected = true;
  DateTime? _lastSync;
  String? _streamError;
  DateTime _todayStart;

  CommandPhase _commandPhase = CommandPhase.idle;
  SystemCommand? _activeCommand;
  String? _commandError;
  Completer<bool>? _ackCompleter;
  Timer? _ackTimer;

  bool _deviceOnline = false;
  bool _deviceEverOnline = false;
  bool _baselineReady = false;
  final Map<WasteCategory, BinLevel> _alertedLevel = {};

  /// Jarak (%) di bawah threshold sebelum peringatan boleh muncul lagi —
  /// mencegah notifikasi berulang akibat noise sensor ultrasonik.
  static const _hysteresis = 3;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void start() {
    _subscribeAll();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _subscribeAll() {
    _listen(repository.watchSystemStatus(), _onSystem);
    _listen(repository.watchBins(), _onBins);
    _listen(repository.watchSettings(), _onSettings);
    _listen(repository.watchNotifications(), _onNotifications);
    _listen(repository.watchLatestCommand(), _onCommand);
    _listen(repository.watchBackendConnection(), _onBackend);
    _subscribeToday();
  }

  void _listen<T>(Stream<T> stream, void Function(T) onData) {
    _subs.add(stream.listen(onData, onError: _onStreamError));
  }

  void _subscribeToday() {
    _todaySub?.cancel();
    _todaySub = repository.watchSortingsSince(_todayStart).listen((list) {
      _today = [...list]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _markSynced();
      _notify();
    }, onError: _onStreamError);
  }

  /// Berlangganan ulang setelah error komunikasi.
  Future<void> retry() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _todaySub?.cancel();
    _streamError = null;
    _systemLoaded = false;
    _binsLoaded = false;
    _settingsLoaded = false;
    _notify();
    _subscribeAll();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ackTimer?.cancel();
    if (_ackCompleter?.isCompleted == false) _ackCompleter!.complete(false);
    for (final s in _subs) {
      s.cancel();
    }
    _todaySub?.cancel();
    _alerts.close();
    repository.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  DateTime get _serverNow => _clock().add(repository.serverTimeOffset);

  // ---------------------------------------------------------------------------
  // Handler stream
  // ---------------------------------------------------------------------------

  void _onStreamError(Object error, [StackTrace? stackTrace]) {
    _streamError = 'Gagal membaca data dari server: $error';
    _notify();
  }

  void _markSynced() {
    _lastSync = _clock();
    _streamError = null;
  }

  void _onSystem(SystemStatus? status) {
    final previous = _system;
    _system = status;
    _systemLoaded = true;
    _markSynced();
    if (previous != null && status != null) {
      _detectAbnormalStop(previous, status);
    }
    _evaluateDevice();
    _checkCommandAck();
    _notify();
  }

  void _onBins(List<WasteBin> bins) {
    _bins = {for (final b in bins) b.category: b};
    _binsLoaded = true;
    _markSynced();
    _evaluateBinAlerts();
    _notify();
  }

  void _onSettings(AppSettings settings) {
    _settings = settings;
    _settingsLoaded = true;
    _markSynced();
    _evaluateBinAlerts();
    _notify();
  }

  void _onNotifications(List<AppNotification> list) {
    _notifications = [...list]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _notify();
  }

  void _onCommand(CommandRecord? record) {
    _latestCommand = record;
  }

  void _onBackend(bool connected) {
    _backendConnected = connected;
    _evaluateDevice();
    _notify();
  }

  void _onTick() {
    var changed = _evaluateDevice();
    final today = startOfDay(_clock());
    if (today != _todayStart) {
      _todayStart = today;
      _today = const [];
      _subscribeToday();
      changed = true;
    }
    if (changed) _notify();
  }

  // ---------------------------------------------------------------------------
  // Deteksi kejadian
  // ---------------------------------------------------------------------------

  bool _computeDeviceOnline() {
    final s = _system;
    if (s == null || !_backendConnected) return false;
    if (s.connection != DeviceConnection.connected) return false;
    final last = s.lastUpdated;
    if (last == null) return false;
    return _serverNow.difference(last) <= AppConfig.deviceStaleAfter;
  }

  /// Mengembalikan `true` bila status online perangkat berubah.
  bool _evaluateDevice() {
    final online = _computeDeviceOnline();
    if (online == _deviceOnline) return false;
    final wasOnline = _deviceOnline;
    _deviceOnline = online;
    final stamp = (_system?.lastUpdated ?? _clock()).millisecondsSinceEpoch;
    if (wasOnline && !online && _backendConnected) {
      _raise(
        id: 'CONNECTION_LOST_$stamp',
        type: NotificationType.connectionLost,
        message: 'Connection lost — sistem pemilah tidak mengirimkan data.',
      );
    } else if (!wasOnline && online && _deviceEverOnline) {
      _raise(
        id: 'INFO_conn_ok_$stamp',
        type: NotificationType.info,
        message: 'Koneksi ke perangkat pulih.',
        push: false,
        read: true,
      );
    }
    if (online) _deviceEverOnline = true;
    return true;
  }

  void _detectAbnormalStop(SystemStatus previous, SystemStatus current) {
    final stamp = (current.lastUpdated ?? _clock()).millisecondsSinceEpoch;
    if (current.hasError && current.errorMessage != previous.errorMessage) {
      _raise(
        id: 'ABNORMAL_STOP_$stamp',
        type: NotificationType.abnormalStop,
        message: 'Sistem berhenti secara tidak normal: '
            '${current.errorMessage}.',
      );
    } else if (previous.conveyorRunning &&
        !current.conveyorRunning &&
        !current.hasError &&
        !_stopWasRequested()) {
      _raise(
        id: 'ABNORMAL_STOP_$stamp',
        type: NotificationType.abnormalStop,
        message: 'Sistem berhenti secara tidak normal — konveyor berhenti '
            'tanpa perintah STOP.',
      );
    }
  }

  bool _stopWasRequested() {
    if (_activeCommand == SystemCommand.stop) return true;
    final c = _latestCommand;
    if (c == null || c.command != SystemCommand.stop) return false;
    return _serverNow.difference(c.issuedAt) < const Duration(minutes: 1);
  }

  void _evaluateBinAlerts() {
    if (!_binsLoaded || !_settingsLoaded) return;
    for (final bin in _bins.values) {
      final level = _settings.levelFor(bin.capacityPercentage);
      final alerted = _alertedLevel[bin.category];
      if (!_baselineReady || alerted == null) {
        // Kondisi awal tidak dinotifikasi ulang.
        _alertedLevel[bin.category] = level;
        continue;
      }
      if (level.index > alerted.index) {
        _alertedLevel[bin.category] = level;
        final pct = Fmt.percent(bin.capacityPercentage);
        final stamp = (bin.lastUpdated ?? _clock()).millisecondsSinceEpoch;
        final isFull = level == BinLevel.full;
        _raise(
          id: '${level.code}_${bin.category.key}_$stamp',
          type: isFull ? NotificationType.full : NotificationType.almostFull,
          category: bin.category,
          message: isFull
              ? 'Tempat sampah ${bin.category.label} penuh — kapasitas $pct.'
              : 'Tempat sampah ${bin.category.label} hampir penuh — '
                  'kapasitas $pct.',
        );
      } else if (level.index < alerted.index &&
          bin.capacityPercentage <
              _settings.thresholdOf(alerted) - _hysteresis) {
        _alertedLevel[bin.category] = level;
      }
    }
    _baselineReady = true;
  }

  void _raise({
    required String id,
    required NotificationType type,
    required String message,
    WasteCategory? category,
    bool push = true,
    bool read = false,
  }) {
    final notification = AppNotification(
      id: id,
      type: type,
      message: message,
      timestamp: _clock(),
      isRead: read,
      category: category,
    );
    _persistNotification(notification);
    if (push && _settings.notificationEnabled) {
      notificationService.show(notification);
      if (!_alerts.isClosed) _alerts.add(notification);
    }
  }

  Future<void> _persistNotification(AppNotification n) async {
    try {
      await repository.addNotification(n);
    } catch (e) {
      debugPrint('Gagal menyimpan notifikasi ${n.id}: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Getter untuk UI
  // ---------------------------------------------------------------------------

  bool get isLoading => !_systemLoaded || !_binsLoaded || !_settingsLoaded;
  bool get isSimulation => repository.isSimulation;
  String get dataSourceLabel => repository.sourceLabel;

  SystemStatus? get system => _system;
  AppSettings get settings => _settings;
  bool get deviceOnline => _deviceOnline;
  bool get backendConnected => _backendConnected;
  DateTime? get lastDeviceUpdate => _system?.lastUpdated;
  DateTime? get lastSync => _lastSync;
  String? get streamError => _streamError;

  /// Peringatan baru yang perlu ditampilkan di dalam aplikasi (snackbar).
  Stream<AppNotification> get alerts => _alerts.stream;

  WasteBin? binFor(WasteCategory category) => _bins[category];

  BinLevel? levelFor(WasteCategory category) {
    final bin = _bins[category];
    return bin == null ? null : _settings.levelFor(bin.capacityPercentage);
  }

  int countBinsAt(BinLevel level) =>
      _bins.values.where((b) => _settings.levelFor(b.capacityPercentage) == level).length;

  OfflineReason? get offlineReason {
    if (_deviceOnline) return null;
    return _backendConnected ? OfflineReason.deviceSilent : OfflineReason.phoneOffline;
  }

  OverallState get overallState {
    if (isLoading) return OverallState.loading;
    if (_streamError != null) return OverallState.error;
    final s = _system;
    if (s == null) return OverallState.waitingDevice;
    if (!_deviceOnline) return OverallState.offline;
    if (s.hasError) return OverallState.error;
    if (!s.isOn) return OverallState.systemOff;
    if (countBinsAt(BinLevel.full) > 0) return OverallState.full;
    if (countBinsAt(BinLevel.almostFull) > 0) return OverallState.warning;
    return OverallState.online;
  }

  List<WasteSorting> get todaySortings => _today;

  Map<WasteCategory, int> get todayCounts {
    final counts = {for (final c in WasteCategory.values) c: 0};
    for (final s in _today) {
      if (s.isSuccess) counts[s.category] = counts[s.category]! + 1;
    }
    return counts;
  }

  int get todayTotal => _today.where((s) => s.isSuccess).length;
  int get todayFailed => _today.where((s) => !s.isSuccess).length;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  List<ActivityEntry> recentActivities({int limit = 6}) {
    final entries = <ActivityEntry>[
      for (final s in _today.take(limit)) ActivityEntry.fromSorting(s),
      for (final n in _notifications.take(limit))
        ActivityEntry.fromNotification(n),
    ]..sort((a, b) => b.time.compareTo(a.time));
    return entries.take(limit).toList();
  }

  // ---------------------------------------------------------------------------
  // Kontrol sistem (PRD §11)
  // ---------------------------------------------------------------------------

  CommandPhase get commandPhase => _commandPhase;
  SystemCommand? get activeCommand => _activeCommand;
  String? get commandError => _commandError;
  bool get isCommandBusy =>
      _commandPhase == CommandPhase.sending ||
      _commandPhase == CommandPhase.awaitingDevice;

  bool get canStart {
    final s = _system;
    return s != null &&
        _deviceOnline &&
        !isCommandBusy &&
        (!s.isOn || !s.conveyorRunning || s.hasError);
  }

  bool get canStop {
    final s = _system;
    return s != null &&
        _deviceOnline &&
        !isCommandBusy &&
        (s.isOn || s.conveyorRunning);
  }

  /// Aplikasi → Firebase → ESP32/STM32 → status diperbarui di aplikasi.
  Future<CommandOutcome> sendCommand(SystemCommand command) async {
    if (isCommandBusy) {
      return const CommandOutcome(false, 'Perintah sebelumnya masih diproses.');
    }
    _activeCommand = command;
    _commandPhase = CommandPhase.sending;
    _commandError = null;
    _notify();

    try {
      await repository
          .sendCommand(command)
          .timeout(AppConfig.commandWriteTimeout);
    } on TimeoutException {
      return _failCommand(
          'Server tidak merespons. Periksa koneksi internet ponsel.');
    } catch (e) {
      return _failCommand('Gagal mengirim perintah: $e');
    }

    _commandPhase = CommandPhase.awaitingDevice;
    _notify();

    final acknowledged = await _awaitDeviceAck(command);
    if (!acknowledged) {
      return _failCommand('Perangkat belum menjalankan perintah '
          '${command.code}. Periksa koneksi alat lalu coba lagi.');
    }

    _commandPhase = CommandPhase.idle;
    _activeCommand = null;
    _notify();
    return CommandOutcome(
      true,
      command == SystemCommand.start
          ? 'Sistem berjalan — konveyor RUNNING.'
          : 'Sistem dihentikan — status OFF, konveyor STOPPED.',
    );
  }

  CommandOutcome _failCommand(String message) {
    _commandPhase = CommandPhase.failed;
    _commandError = message;
    _activeCommand = null;
    _notify();
    return CommandOutcome(false, message);
  }

  void dismissCommandError() {
    if (_commandPhase != CommandPhase.failed) return;
    _commandPhase = CommandPhase.idle;
    _commandError = null;
    _notify();
  }

  bool _matches(SystemCommand command, SystemStatus? s) {
    if (s == null) return false;
    return switch (command) {
      SystemCommand.start => s.isOn && s.conveyorRunning && !s.hasError,
      SystemCommand.stop => !s.isOn && !s.conveyorRunning,
    };
  }

  Future<bool> _awaitDeviceAck(SystemCommand command) {
    if (_matches(command, _system)) return Future.value(true);
    final completer = Completer<bool>();
    _ackCompleter = completer;
    _ackTimer = Timer(AppConfig.commandAckTimeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future.whenComplete(() {
      _ackTimer?.cancel();
      _ackCompleter = null;
    });
  }

  void _checkCommandAck() {
    final command = _activeCommand;
    final completer = _ackCompleter;
    if (command == null || completer == null || completer.isCompleted) return;
    if (_matches(command, _system)) completer.complete(true);
  }

  // ---------------------------------------------------------------------------
  // Aksi lain
  // ---------------------------------------------------------------------------

  Future<void> markNotificationRead(String id) =>
      repository.markNotificationRead(id);

  Future<void> markAllNotificationsRead() => repository.markAllNotificationsRead(
      [for (final n in _notifications) if (!n.isRead) n.id]);

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings.sanitized();
    _evaluateBinAlerts();
    _notify();
    await repository.updateSettings(_settings);
  }

  Future<List<WasteSorting>> fetchHistory(DateTime from, DateTime to) =>
      repository.fetchSortings(from, to);
}
