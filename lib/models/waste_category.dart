import 'package:flutter/material.dart';

/// Empat kategori sampah yang dipilah oleh sistem.
enum WasteCategory {
  organik(
    key: 'organik',
    label: 'Organik',
    examples: ['Sisa makanan', 'Daun'],
  ),
  recyclable(
    key: 'recyclable',
    label: 'Recyclable',
    examples: ['Botol plastik', 'Kertas'],
  ),
  logam(
    key: 'logam',
    label: 'Logam',
    examples: ['Kaleng minuman'],
  ),
  anorganik(
    key: 'anorganik',
    label: 'Anorganik',
    examples: ['Kantong kresek', 'Sedotan', 'Styrofoam', 'Residu lainnya'],
  );

  const WasteCategory({
    required this.key,
    required this.label,
    required this.examples,
  });

  /// Kunci yang dipakai di database (`bins/<key>`, field `category`).
  final String key;
  final String label;
  final List<String> examples;

  IconData get icon => switch (this) {
        WasteCategory.organik => Icons.compost_rounded,
        WasteCategory.recyclable => Icons.recycling_rounded,
        WasteCategory.logam => Icons.propane_tank_outlined,
        WasteCategory.anorganik => Icons.delete_outline_rounded,
      };

  static const _aliases = {
    'organic': WasteCategory.organik,
    'recycle': WasteCategory.recyclable,
    'metal': WasteCategory.logam,
    'residual': WasteCategory.anorganik,
    'residu': WasteCategory.anorganik,
    'inorganic': WasteCategory.anorganik,
  };

  /// Menerima kunci database, label, atau alias bahasa Inggris dari firmware.
  static WasteCategory? tryParse(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim().toLowerCase();
    for (final c in WasteCategory.values) {
      if (c.key == text || c.label.toLowerCase() == text) return c;
    }
    return _aliases[text];
  }
}
