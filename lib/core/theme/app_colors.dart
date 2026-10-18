import 'package:flutter/material.dart';

import '../../models/waste_category.dart';

/// Warna status — sama di mode terang & gelap, sengaja berbeda dari warna
/// kategori, dan selalu dipasangkan dengan ikon + label (bukan warna saja).
abstract final class StatusColors {
  static const good = Color(0xFF0CA30C);
  static const warning = Color(0xFFFAB219);
  static const serious = Color(0xFFEC835A);
  static const critical = Color(0xFFD03B3B);
}

/// Warna tombol aksi dengan teks putih (kontras ≥ 4.5:1).
abstract final class ActionColors {
  static const start = Color(0xFF0A7A0A);
  static const stop = Color(0xFFC62F2F);
}

enum StatusTone { good, warning, serious, critical, neutral }

/// Token warna aplikasi untuk satu mode (terang/gelap).
///
/// Warna kategori telah divalidasi (lightness band, chroma, separasi
/// buta warna untuk pasangan bersebelahan termasuk wrap-around donut)
/// pada urutan Organik → Recyclable → Logam → Anorganik.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.page,
    required this.surface,
    required this.surfaceMuted,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.grid,
    required this.baseline,
    required this.border,
    required this.track,
    required this.selection,
    required this.organik,
    required this.recyclable,
    required this.logam,
    required this.anorganik,
  });

  final Color page;
  final Color surface;
  final Color surfaceMuted;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final Color grid;
  final Color baseline;
  final Color border;
  final Color track;
  final Color selection;
  final Color organik;
  final Color recyclable;
  final Color logam;
  final Color anorganik;

  static const light = AppPalette(
    page: Color(0xFFF3F3F0),
    surface: Color(0xFFFCFCFB),
    surfaceMuted: Color(0xFFF1F0EC),
    inkPrimary: Color(0xFF0B0B0B),
    inkSecondary: Color(0xFF52514E),
    inkMuted: Color(0xFF898781),
    grid: Color(0xFFE1E0D9),
    baseline: Color(0xFFC3C2B7),
    border: Color(0x1A0B0B0B),
    track: Color(0xFFE9E8E2),
    selection: Color(0xFFE4E3DC),
    organik: Color(0xFF008300),
    recyclable: Color(0xFF2A78D6),
    logam: Color(0xFFEDA100),
    anorganik: Color(0xFFE87BA4),
  );

  static const dark = AppPalette(
    page: Color(0xFF0D0D0D),
    surface: Color(0xFF1A1A19),
    surfaceMuted: Color(0xFF242423),
    inkPrimary: Color(0xFFFFFFFF),
    inkSecondary: Color(0xFFC3C2B7),
    inkMuted: Color(0xFF898781),
    grid: Color(0xFF2C2C2A),
    baseline: Color(0xFF383835),
    border: Color(0x1AFFFFFF),
    track: Color(0xFF2C2C2A),
    selection: Color(0xFF30302E),
    organik: Color(0xFF008300),
    recyclable: Color(0xFF3987E5),
    logam: Color(0xFFC98500),
    anorganik: Color(0xFFD55181),
  );

  Color category(WasteCategory c) => switch (c) {
        WasteCategory.organik => organik,
        WasteCategory.recyclable => recyclable,
        WasteCategory.logam => logam,
        WasteCategory.anorganik => anorganik,
      };

  Color tone(StatusTone t) => switch (t) {
        StatusTone.good => StatusColors.good,
        StatusTone.warning => StatusColors.warning,
        StatusTone.serious => StatusColors.serious,
        StatusTone.critical => StatusColors.critical,
        StatusTone.neutral => inkMuted,
      };

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
