import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'features/shell/home_shell.dart';

class TrashMonitorApp extends StatelessWidget {
  const TrashMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeController.instance,
      builder: (context, mode, _) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        locale: const Locale('id', 'ID'),
        supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomeShell(),
      ),
    );
  }
}
