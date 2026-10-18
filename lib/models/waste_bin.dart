import 'parsing.dart';
import 'waste_category.dart';

/// Tingkat kepenuhan tempat sampah, dihitung dari ambang di Pengaturan.
enum BinLevel {
  normal('NORMAL', 'Normal'),
  almostFull('ALMOST_FULL', 'Hampir Penuh'),
  full('FULL', 'Penuh');

  const BinLevel(this.code, this.label);
  final String code;
  final String label;
}

/// Node `bins/<category>` — diperbarui ESP32 dari sensor ultrasonik.
class WasteBin {
  const WasteBin({
    required this.id,
    required this.category,
    required this.capacityPercentage,
    this.status,
    this.lastUpdated,
  });

  final String id;
  final WasteCategory category;

  /// 0–100, hasil konversi jarak ultrasonik ke persen kapasitas.
  final double capacityPercentage;

  /// Status yang dilaporkan perangkat (informatif). Aplikasi menghitung ulang
  /// status dari ambang di Pengaturan agar perubahan threshold langsung berlaku.
  final String? status;
  final DateTime? lastUpdated;

  static WasteBin? tryFromMap(String key, Map<String, dynamic> map) {
    final category =
        WasteCategory.tryParse(map['category']) ?? WasteCategory.tryParse(key);
    final pct = asDouble(map['capacity_percentage']);
    if (category == null || pct == null) return null;
    return WasteBin(
      id: asNonEmptyString(map['id']) ?? key,
      category: category,
      capacityPercentage: pct.clamp(0, 100).toDouble(),
      status: asNonEmptyString(map['status']),
      lastUpdated: asDateTime(map['last_updated']),
    );
  }

  WasteBin copyWith({
    double? capacityPercentage,
    String? status,
    DateTime? lastUpdated,
  }) {
    return WasteBin(
      id: id,
      category: category,
      capacityPercentage: capacityPercentage ?? this.capacityPercentage,
      status: status ?? this.status,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'category': category.key,
        'capacity_percentage': capacityPercentage,
        'status': status,
        'last_updated': lastUpdated?.millisecondsSinceEpoch,
      };
}
