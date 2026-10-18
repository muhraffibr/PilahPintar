import 'parsing.dart';
import 'waste_bin.dart';

/// Pengaturan yang disimpan di `settings` (dipakai bersama oleh semua ponsel).
class AppSettings {
  const AppSettings({
    this.notificationEnabled = true,
    this.almostFullThreshold = defaultAlmostFull,
    this.fullThreshold = defaultFull,
  });

  static const defaultAlmostFull = 70;
  static const defaultFull = 90;
  static const minAlmostFull = 50;
  static const maxFull = 100;

  /// Jarak minimum antara ambang "hampir penuh" dan "penuh".
  static const minGap = 5;

  static const defaults = AppSettings();

  final bool notificationEnabled;
  final int almostFullThreshold;
  final int fullThreshold;

  /// Normal: < hampir penuh · Hampir penuh: hampir penuh – (penuh − 1) ·
  /// Penuh: ≥ penuh.
  BinLevel levelFor(double capacityPercentage) {
    if (capacityPercentage >= fullThreshold) return BinLevel.full;
    if (capacityPercentage >= almostFullThreshold) return BinLevel.almostFull;
    return BinLevel.normal;
  }

  int thresholdOf(BinLevel level) => switch (level) {
        BinLevel.full => fullThreshold,
        BinLevel.almostFull => almostFullThreshold,
        BinLevel.normal => 0,
      };

  AppSettings copyWith({
    bool? notificationEnabled,
    int? almostFullThreshold,
    int? fullThreshold,
  }) {
    return AppSettings(
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      almostFullThreshold: almostFullThreshold ?? this.almostFullThreshold,
      fullThreshold: fullThreshold ?? this.fullThreshold,
    ).sanitized();
  }

  /// Menjaga ambang tetap valid: 50 ≤ hampir penuh ≤ penuh − 5 ≤ 95.
  AppSettings sanitized() {
    final full = fullThreshold.clamp(minAlmostFull + minGap, maxFull);
    final almost = almostFullThreshold.clamp(minAlmostFull, full - minGap);
    return AppSettings(
      notificationEnabled: notificationEnabled,
      almostFullThreshold: almost,
      fullThreshold: full,
    );
  }

  factory AppSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    return AppSettings(
      notificationEnabled: asBool(map['notification_enabled']) ?? true,
      almostFullThreshold:
          asInt(map['almost_full_threshold']) ?? defaultAlmostFull,
      fullThreshold: asInt(map['full_threshold']) ?? defaultFull,
    ).sanitized();
  }

  Map<String, Object?> toMap() => {
        'notification_enabled': notificationEnabled,
        'almost_full_threshold': almostFullThreshold,
        'full_threshold': fullThreshold,
      };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.notificationEnabled == notificationEnabled &&
      other.almostFullThreshold == almostFullThreshold &&
      other.fullThreshold == fullThreshold;

  @override
  int get hashCode =>
      Object.hash(notificationEnabled, almostFullThreshold, fullThreshold);
}
