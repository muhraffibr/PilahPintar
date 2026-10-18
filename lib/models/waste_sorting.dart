import 'parsing.dart';
import 'waste_category.dart';

enum SortingStatus {
  success('SUCCESS', 'Berhasil'),
  failed('FAILED', 'Gagal');

  const SortingStatus(this.code, this.label);
  final String code;
  final String label;

  static SortingStatus parse(Object? value) {
    final text = value?.toString().toUpperCase();
    return text == 'FAILED' || text == 'GAGAL' || text == 'ERROR'
        ? SortingStatus.failed
        : SortingStatus.success;
  }
}

/// Satu kejadian pemilahan (`sortings/<pushId>`) yang ditulis ESP32.
class WasteSorting {
  const WasteSorting({
    required this.id,
    required this.category,
    required this.timestamp,
    required this.status,
    this.item,
  });

  final String id;
  final WasteCategory category;
  final DateTime timestamp;
  final SortingStatus status;

  /// Jenis benda bila terdeteksi (mis. "Botol plastik"). Opsional.
  final String? item;

  bool get isSuccess => status == SortingStatus.success;

  /// "Botol plastik berhasil dipilah" / "Sampah organik berhasil dipilah".
  String get description {
    final subject = item ?? 'Sampah ${category.label.toLowerCase()}';
    return isSuccess ? '$subject berhasil dipilah' : '$subject gagal dipilah';
  }

  static WasteSorting? tryFromMap(String key, Map<String, dynamic> map) {
    final category = WasteCategory.tryParse(map['category']);
    final timestamp = asDateTime(map['timestamp']);
    if (category == null || timestamp == null) return null;
    return WasteSorting(
      id: asNonEmptyString(map['id']) ?? key,
      category: category,
      timestamp: timestamp,
      status: SortingStatus.parse(map['status']),
      item: asNonEmptyString(map['item']),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'category': category.key,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'status': status.code,
        'item': item,
      };
}
