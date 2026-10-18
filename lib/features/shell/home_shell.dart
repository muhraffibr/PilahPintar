import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/app_notification.dart';
import '../../state/monitoring_controller.dart';
import '../../widgets/status_ui.dart';
import '../dashboard/dashboard_screen.dart';
import '../history/history_screen.dart';
import '../notifications/notification_panel_screen.dart';
import '../settings/settings_screen.dart';

/// Navigasi utama: Dashboard · Riwayat · Pengaturan (PRD §4).
/// Aplikasi langsung membuka Dashboard — tanpa login.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<AppNotification>? _alertSub;

  @override
  void initState() {
    super.initState();
    _alertSub = context.read<MonitoringController>().alerts.listen(_showAlert);
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    super.dispose();
  }

  /// Peringatan baru juga ditampilkan di dalam aplikasi (selain push).
  void _showAlert(AppNotification n) {
    if (!mounted) return;
    final p = context.palette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            Icon(n.type.icon, color: p.tone(n.type.tone)),
            const SizedBox(width: 12),
            Expanded(child: Text(n.message)),
          ],
        ),
        action: SnackBarAction(
          label: 'Lihat',
          onPressed: () => NotificationPanelScreen.open(context),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(onOpenHistory: () => setState(() => _index = 1)),
          const HistoryScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Riwayat',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}
