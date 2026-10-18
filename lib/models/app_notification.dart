import 'parsing.dart';
import 'waste_category.dart';

enum NotificationType {
  almostFull('ALMOST_FULL', 'Hampir penuh'),
  full('FULL', 'Tempat sampah penuh'),
  connectionLost('CONNECTION_LOST', 'Koneksi terputus'),
  abnormalStop('ABNORMAL_STOP', 'Sistem berhenti tidak normal'),
  info('INFO', 'Informasi');

  const NotificationType(this.code, this.title);
  final String code;
  final String title;

  static NotificationType parse(Object? value) {
    final text = value?.toString().toUpperCase();
    for (final t in NotificationType.values) {
      if (t.code == text) return t;
    }
    return NotificationType.info;
  }
}

/// Node `notifications/<id>`.
///
/// ID dibuat deterministik dari kejadian (mis. `FULL_logam_<timestamp>`)
/// sehingga beberapa ponsel yang mendeteksi kejadian yang sama tidak
/// membuat entri ganda.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.isRead,
    this.category,
  });

  final String id;
  final NotificationType type;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final WasteCategory? category;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        message: message,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
        category: category,
      );

  static AppNotification? tryFromMap(String key, Map<String, dynamic> map) {
    final message = asNonEmptyString(map['message']);
    final timestamp = asDateTime(map['timestamp']);
    if (message == null || timestamp == null) return null;
    return AppNotification(
      id: asNonEmptyString(map['id']) ?? key,
      type: NotificationType.parse(map['type']),
      message: message,
      timestamp: timestamp,
      isRead: asBool(map['is_read']) ?? false,
      category: WasteCategory.tryParse(map['category']),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.code,
        'message': message,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'is_read': isRead,
        'category': category?.key,
      };
}
