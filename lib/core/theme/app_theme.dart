import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.inkPrimary,
      onPrimary: p.surface,
      primaryContainer: p.selection,
      onPrimaryContainer: p.inkPrimary,
      secondary: p.inkSecondary,
      onSecondary: p.surface,
      secondaryContainer: p.selection,
      onSecondaryContainer: p.inkPrimary,
      error: StatusColors.critical,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.inkPrimary,
      onSurfaceVariant: p.inkSecondary,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.surfaceMuted,
      outline: p.baseline,
      outlineVariant: p.grid,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final text = base.textTheme.apply(
      bodyColor: p.inkPrimary,
      displayColor: p.inkPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: p.page,
      extensions: [p],
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: text.bodySmall?.copyWith(color: p.inkSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.page,
        foregroundColor: p.inkPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.selection,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.grid, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.selection,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: text.labelLarge,
        showCheckmark: false,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.inkPrimary,
        inactiveTrackColor: p.track,
        thumbColor: p.inkPrimary,
        overlayColor: p.inkPrimary.withValues(alpha: 0.08),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.inkPrimary,
        linearTrackColor: p.track,
        circularTrackColor: p.track,
      ),
      listTileTheme: ListTileThemeData(iconColor: p.inkSecondary),
    );
  }
}
