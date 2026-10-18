import 'parsing.dart';

enum PowerState { on, off }

enum ConveyorState { running, stopped }

enum DeviceConnection { connected, disconnected }

/// Node `system_status` — ditulis ESP32 sebagai heartbeat (±5 detik sekali).
class SystemStatus {
  const SystemStatus({
    required this.system,
    required this.conveyor,
    required this.connection,
    this.lastUpdated,
    this.errorMessage,
  });

  final PowerState system;
  final ConveyorState conveyor;
  final DeviceConnection connection;
  final DateTime? lastUpdated;

  /// Diisi perangkat bila terjadi gangguan (mis. konveyor macet).
  final String? errorMessage;

  bool get isOn => system == PowerState.on;
  bool get conveyorRunning => conveyor == ConveyorState.running;
  bool get hasError => errorMessage != null;

  factory SystemStatus.fromMap(Map<String, dynamic> map) {
    String upper(Object? v) => v?.toString().trim().toUpperCase() ?? '';
    return SystemStatus(
      system: const {'ON', 'ONLINE', 'TRUE', '1'}.contains(upper(map['system_status']))
          ? PowerState.on
          : PowerState.off,
      conveyor: const {'RUNNING', 'ON', 'TRUE', '1'}
              .contains(upper(map['conveyor_status']))
          ? ConveyorState.running
          : ConveyorState.stopped,
      connection: upper(map['connection_status']) == 'DISCONNECTED'
          ? DeviceConnection.disconnected
          : DeviceConnection.connected,
      lastUpdated: asDateTime(map['last_updated']),
      errorMessage: asNonEmptyString(map['error']),
    );
  }

  SystemStatus copyWith({
    PowerState? system,
    ConveyorState? conveyor,
    DeviceConnection? connection,
    DateTime? lastUpdated,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SystemStatus(
      system: system ?? this.system,
      conveyor: conveyor ?? this.conveyor,
      connection: connection ?? this.connection,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, Object?> toMap() => {
        'system_status': isOn ? 'ON' : 'OFF',
        'conveyor_status': conveyorRunning ? 'RUNNING' : 'STOPPED',
        'connection_status':
            connection == DeviceConnection.connected ? 'CONNECTED' : 'DISCONNECTED',
        'last_updated': lastUpdated?.millisecondsSinceEpoch,
        'error': errorMessage,
      };
}
