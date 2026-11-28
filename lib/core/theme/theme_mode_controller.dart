import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pilihan tema terang/gelap yang dipilih pengguna lewat switch di
/// Pengaturan. Sebelum pengguna memilih, tema mengikuti pengaturan ponsel.
/// Pilihan disimpan di perangkat (shared_preferences), jadi tetap berlaku
/// setelah aplikasi ditutup.
class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController._() : super(ThemeMode.system);

  static final instance = ThemeModeController._();

  static const _prefKey = 'theme_mode';

  /// Dipanggil sekali di main() sebelum runApp.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = switch (prefs.getString(_prefKey)) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Penyimpanan tidak tersedia: tetap ikuti tema ponsel.
    }
  }

  /// `true` bila tema yang tampil saat ini gelap (termasuk saat masih
  /// mengikuti pengaturan ponsel).
  bool isDark(BuildContext context) => switch (value) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system =>
          MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      };

  Future<void> setDark(bool dark) async {
    value = dark ? ThemeMode.dark : ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, dark ? 'dark' : 'light');
    } catch (_) {
      // Pilihan tetap berlaku sampai aplikasi ditutup.
    }
  }
}
