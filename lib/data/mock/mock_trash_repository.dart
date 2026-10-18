import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_notification.dart';
import '../../models/app_settings.dart';
import '../../models/system_command.dart';
import '../../models/system_status.dart';
import '../../models/waste_bin.dart';
import '../../models/waste_category.dart';
import '../../models/waste_sorting.dart';
import '../trash_repository.dart';
import 'mock_data_generator.dart';

/// Sumber data simulasi — meniru perilaku ESP32 + Firebase tanpa backend.
///
/// * Konveyor yang berjalan memilah ±1 item tiap 3–4 detik.
/// * Kapasitas tempat sampah naik sesuai item yang masuk; tempat sampah yang
///   penuh dikosongkan "petugas" ±25 detik kemudian agar demo terus berjalan.
/// * Heartbeat dikirim tiap 5 detik; memutus koneksi perangkat (lihat
///   [setDeviceOnline]) menghentikan heartbeat sehingga aplikasi mendeteksi
///   offline secara alami, sama seperti perangkat sungguhan.
class MockTrashRepository implements TrashRepository {
  MockTrashRepository({
    SharedPreferences? prefs,
    bool simulate = true,
    Duration startupDelay = const Duration(milliseconds: 1200),
    int seed = 2026,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _rng = Random(seed),
        _clock = clock ?? DateTime.now {
    final now = _clock();
    final settings = _loadSettings();
    _settings = _ValueSubject(settings);
    _system = _ValueSubject(SystemStatus(
      system: PowerState.on,
      conveyor: ConveyorState.running,
      connection: DeviceConnection.connected,
      lastUpdated: now,
    ));
    _bins = _ValueSubject(MockDataGenerator.initialBins(now, settings));
    _notifications = _ValueSubject({
      for (final n in MockDataGenerator.seedNotifications(now)) n.id: n,
    });
    _sortings.addAll(MockDataGenerator.history(now: now, rng: _rng));

    _ready = Future<void>.delayed(startupDelay);
    if (simulate) {
      _ready.then((_) {
        if (_disposed) return;
        _tickTimer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
        _heartbeatTimer =
            Timer.periodic(const Duration(seconds: 5), (_) => _heartbeat());
      });
    }
  }

  static Future<MockTrashRepository> create() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null; // Pengaturan tidak dipersist, aplikasi tetap berjalan.
    }
    return MockTrashRepository(prefs: prefs);
  }

  final SharedPreferences? _prefs;
  final Random _rng;
  final DateTime Function() _clock;

  late final _ValueSubject<AppSettings> _settings;
  late final _ValueSubject<SystemStatus?> _system;
  late final _ValueSubject<List<WasteBin>> _bins;
  late final _ValueSubject<Map<String, AppNotification>> _notifications;
  final _command = _ValueSubject<CommandRecord?>(null);
  final _backend = _ValueSubject<bool>(true);
  final List<WasteSorting> _sortings = [];
  final _sortingsChanged = StreamController<void>.broadcast();
  final Map<WasteCategory, DateTime> _fullSince = {};

  late final Future<void> _ready;
  Timer? _tickTimer;
  Timer? _heartbeatTimer;
  bool _deviceOnline = true;
  bool _disposed = false;
  int _idCounter = 0;

  @override
  String get sourceLabel => 'Simulasi (mock data)';

  @override
  bool get isSimulation => true;

  @override
  Duration get serverTimeOffset => Duration.zero;

  // ---------------------------------------------------------------------------
  // Stream & query
  // ---------------------------------------------------------------------------

  Stream<T> _afterReady<T>(Stream<T> Function() source) =>
      Stream.fromFuture(_ready).asyncExpand((_) => source());

  @override
  Stream<SystemStatus?> watchSystemStatus() => _afterReady(() => _system.stream);

  @override
  Stream<List<WasteBin>> watchBins() => _afterReady(() => _bins.stream);

  @override
  Stream<AppSettings> watchSettings() => _afterReady(() => _settings.stream);

  @override
  Stream<List<AppNotification>> watchNotifications({int limit = 50}) =>
      _afterReady(() => _notifications.stream.map((all) {
            final list = all.values.toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
            return list.take(limit).toList();
          }));

  @override
  Stream<CommandRecord?> watchLatestCommand() =>
      _afterReady(() => _command.stream);

  @override
  Stream<bool> watchBackendConnection() => _backend.stream;

  @override
  Stream<List<WasteSorting>> watchSortingsSince(DateTime since) {
    return _afterReady(() => Stream.multi((controller) {
          void emit() => controller.add([
                for (final s in _sortings)
                  if (!s.timestamp.isBefore(since)) s,
              ]);
          emit();
          final sub = _sortingsChanged.stream.listen((_) => emit());
          controller.onCancel = sub.cancel;
        }));
  }

  @override
  Future<List<WasteSorting>> fetchSortings(DateTime from, DateTime to) async {
    await _ready;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return [
      for (final s in _sortings)
        if (!s.timestamp.isBefore(from) && !s.timestamp.isAfter(to)) s,
    ];
  }

  // ---------------------------------------------------------------------------
  // Perintah & tulis data
  // ---------------------------------------------------------------------------

  @override
  Future<void> sendCommand(SystemCommand command) async {
    await _ready;
    // Waktu tulis ke "server".
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final record = CommandRecord(
      command: command,
      issuedAt: _clock(),
      status: CommandStatus.pending,
    );
    _command.value = record;

    // ESP32 membaca perintah lalu meneruskan ke STM32. Perangkat yang offline
    // tidak pernah mengeksekusi — aplikasi akan menunggu hingga timeout.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (_disposed || !_deviceOnline) return;
      final current = _system.value;
      if (current == null) return;
      final now = _clock();
      _system.value = switch (command) {
        SystemCommand.start => current.copyWith(
            system: PowerState.on,
            conveyor: ConveyorState.running,
            connection: DeviceConnection.connected,
            lastUpdated: now,
            clearError: true,
          ),
        SystemCommand.stop => current.copyWith(
            system: PowerState.off,
            conveyor: ConveyorState.stopped,
            lastUpdated: now,
          ),
      };
      _command.value = record.copyWith(status: CommandStatus.done);
    });
  }

  @override
  Future<void> addNotification(AppNotification notification) async {
    final current = _notifications.value;
    if (current.containsKey(notification.id)) return;
    _notifications.value = {...current, notification.id: notification};
  }

  @override
  Future<void> markNotificationRead(String id) async {
    final current = _notifications.value;
    final n = current[id];
    if (n == null || n.isRead) return;
    _notifications.value = {...current, id: n.copyWith(isRead: true)};
  }

  @override
  Future<void> markAllNotificationsRead(List<String> ids) async {
    final next = Map.of(_notifications.value);
    for (final id in ids) {
      final n = next[id];
      if (n != null) next[id] = n.copyWith(isRead: true);
    }
    _notifications.value = next;
  }

  @override
  Future<void> updateSettings(AppSettings settings) async {
    final s = settings.sanitized();
    _settings.value = s;
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.setBool('notification_enabled', s.notificationEnabled);
      await prefs.setInt('almost_full_threshold', s.almostFullThreshold);
      await prefs.setInt('full_threshold', s.fullThreshold);
    }
  }

  AppSettings _loadSettings() {
    final prefs = _prefs;
    if (prefs == null) return AppSettings.defaults;
    return AppSettings(
      notificationEnabled: prefs.getBool('notification_enabled') ?? true,
      almostFullThreshold: prefs.getInt('almost_full_threshold') ??
          AppSettings.defaultAlmostFull,
      fullThreshold:
          prefs.getInt('full_threshold') ?? AppSettings.defaultFull,
    ).sanitized();
  }

  // ---------------------------------------------------------------------------
  // Kontrol simulasi (hanya untuk demo — dipanggil dari halaman Pengaturan)
  // ---------------------------------------------------------------------------

  bool get deviceOnline => _deviceOnline;

  /// Memutus/menyambung perangkat. Saat terputus, heartbeat berhenti dan
  /// aplikasi mendeteksi offline setelah data dianggap basi.
  void setDeviceOnline(bool online) {
    _deviceOnline = online;
    if (online) _heartbeat();
  }

  /// Konveyor macet: STM32 menghentikan motor dan ESP32 melaporkan error.
  void simulateConveyorFault() {
    final current = _system.value;
    if (current == null || !_deviceOnline) return;
    _system.value = current.copyWith(
      conveyor: ConveyorState.stopped,
      lastUpdated: _clock(),
      errorMessage: 'Konveyor macet — STM32 mendeteksi arus motor berlebih',
    );
  }

  void emptyBin(WasteCategory category) {
    _setCapacity(category, 3 + _rng.nextDouble() * 5);
    _fullSince.remove(category);
    final now = _clock();
    addNotification(AppNotification(
      id: 'INFO_empty_${category.key}_${now.millisecondsSinceEpoch}',
      type: NotificationType.info,
      message: 'Tempat sampah ${category.label} telah dikosongkan petugas.',
      timestamp: now,
      isRead: true,
      category: category,
    ));
  }

  void emptyAllBins() {
    for (final c in WasteCategory.values) {
      emptyBin(c);
    }
  }

  void addCapacity(WasteCategory category, double delta) {
    final bin = _binOf(category);
    if (bin == null) return;
    _setCapacity(category, bin.capacityPercentage + delta);
  }

  // ---------------------------------------------------------------------------
  // Simulasi internal
  // ---------------------------------------------------------------------------

  WasteBin? _binOf(WasteCategory category) {
    for (final b in _bins.value) {
      if (b.category == category) return b;
    }
    return null;
  }

  void _setCapacity(WasteCategory category, double pct) {
    final now = _clock();
    final value = pct.clamp(0, 100).toDouble();
    _bins.value = [
      for (final b in _bins.value)
        if (b.category == category)
          b.copyWith(
            capacityPercentage: value,
            status: _settings.value.levelFor(value).code,
            lastUpdated: now,
          )
        else
          b,
    ];
  }

  void _tick() {
    if (_disposed) return;
    final s = _system.value;
    final running = _deviceOnline &&
        s != null &&
        s.isOn &&
        s.conveyorRunning &&
        !s.hasError;
    if (running && _rng.nextDouble() < 0.8) _sortOne();
    _autoEmpty();
  }

  void _sortOne() {
    final category = MockDataGenerator.pickCategory(_rng);
    final success = _rng.nextDouble() > 0.03;
    _sortings.add(WasteSorting(
      id: 'srt_${_clock().millisecondsSinceEpoch}_${_idCounter++}',
      category: category,
      timestamp: _clock(),
      status: success ? SortingStatus.success : SortingStatus.failed,
      item: MockDataGenerator.pickItem(category, _rng),
    ));
    _sortingsChanged.add(null);
    if (success) {
      final delta = MockDataGenerator.fillPerItem[category]! *
          (0.8 + _rng.nextDouble() * 0.4);
      addCapacity(category, delta);
    }
  }

  void _autoEmpty() {
    if (!_deviceOnline) return;
    final now = _clock();
    for (final bin in _bins.value) {
      if (bin.capacityPercentage < 99) {
        _fullSince.remove(bin.category);
        continue;
      }
      final since = _fullSince.putIfAbsent(bin.category, () => now);
      if (now.difference(since) > const Duration(seconds: 25)) {
        emptyBin(bin.category);
      }
    }
  }

  void _heartbeat() {
    if (_disposed || !_deviceOnline) return;
    final now = _clock();
    final s = _system.value;
    if (s != null) {
      _system.value = s.copyWith(
        lastUpdated: now,
        connection: DeviceConnection.connected,
      );
    }
    _bins.value = [for (final b in _bins.value) b.copyWith(lastUpdated: now)];
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _tickTimer?.cancel();
    _heartbeatTimer?.cancel();
    await Future.wait([
      _sortingsChanged.close(),
      _settings.close(),
      _system.close(),
      _bins.close(),
      _notifications.close(),
      _command.close(),
      _backend.close(),
    ]);
  }
}

/// Nilai terkini + stream perubahan; pelanggan baru langsung menerima nilai
/// terakhir (seperti `onValue` di Firebase).
class _ValueSubject<T> {
  _ValueSubject(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Stream<T> get stream => Stream.multi((controller) {
        controller.add(_value);
        final sub = _controller.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = sub.cancel;
      });

  Future<void> close() => _controller.close();
}
