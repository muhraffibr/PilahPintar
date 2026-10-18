import 'parsing.dart';

enum SystemCommand {
  start('START'),
  stop('STOP');

  const SystemCommand(this.code);
  final String code;

  static SystemCommand? tryParse(Object? value) {
    final text = value?.toString().toUpperCase();
    for (final c in SystemCommand.values) {
      if (c.code == text) return c;
    }
    return null;
  }
}

enum CommandStatus {
  pending('PENDING'),
  acknowledged('ACK'),
  done('DONE'),
  failed('FAILED');

  const CommandStatus(this.code);
  final String code;

  static CommandStatus parse(Object? value) {
    final text = value?.toString().toUpperCase();
    for (final s in CommandStatus.values) {
      if (s.code == text) return s;
    }
    return CommandStatus.pending;
  }
}

/// Node `commands/latest` — ditulis aplikasi, dibaca & dikonfirmasi ESP32.
class CommandRecord {
  const CommandRecord({
    required this.command,
    required this.issuedAt,
    required this.status,
    this.source = 'mobile_app',
  });

  final SystemCommand command;
  final DateTime issuedAt;
  final CommandStatus status;
  final String source;

  static CommandRecord? tryFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final command = SystemCommand.tryParse(map['command']);
    final issuedAt = asDateTime(map['issued_at']);
    if (command == null || issuedAt == null) return null;
    return CommandRecord(
      command: command,
      issuedAt: issuedAt,
      status: CommandStatus.parse(map['status']),
      source: asNonEmptyString(map['source']) ?? 'unknown',
    );
  }

  CommandRecord copyWith({CommandStatus? status}) => CommandRecord(
        command: command,
        issuedAt: issuedAt,
        status: status ?? this.status,
        source: source,
      );
}
