import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../state/monitoring_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';
import '../notifications/notification_panel_screen.dart';
import 'widgets/bin_capacity_grid.dart';
import 'widgets/connection_banner.dart';
import 'widgets/distribution_charts.dart';
import 'widgets/recent_activity_card.dart';
import 'widgets/sorting_stats_card.dart';
import 'widgets/system_control_card.dart';
import 'widgets/system_status_card.dart';

/// Halaman utama — urutan sesuai prioritas PRD §12:
/// status → kapasitas → kontrol → statistik → aktivitas.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenHistory});

  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);

    final Widget body = switch (c.overallState) {
      OverallState.loading =>
        const LoadingView(message: 'Mengambil data dari sistem…'),
      OverallState.waitingDevice => const _WaitingDeviceView(),
      OverallState.error when c.streamError != null && c.system == null =>
        EmptyState(
          icon: Icons.sync_problem_rounded,
          title: 'Terjadi masalah komunikasi',
          message: c.streamError,
          action: FilledButton(onPressed: c.retry, child: const Text('Coba lagi')),
        ),
      _ => _DashboardContent(onOpenHistory: onOpenHistory),
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dashboard'),
            Text(
              '${AppConfig.appName} · ${AppConfig.schoolName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: const [NotificationBellButton(), SizedBox(width: 8)],
      ),
      body: body,
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.onOpenHistory});

  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ConnectionBanner(),
              const SystemStatusCard(),
              const SectionHeader(
                title: 'Kapasitas Tempat Sampah',
                subtitle: 'Sensor ultrasonik · ketuk kartu untuk detail',
              ),
              const BinCapacityGrid(),
              const SectionHeader(title: 'Kontrol Sistem'),
              const SystemControlCard(),
              const SectionHeader(title: 'Statistik Pemilahan'),
              const SortingStatsCard(),
              const SectionHeader(title: 'Distribusi Sampah'),
              const DistributionCharts(),
              SectionHeader(
                title: 'Aktivitas Terbaru',
                trailing: TextButton(
                  onPressed: onOpenHistory,
                  child: const Text('Lihat riwayat'),
                ),
              ),
              const RecentActivityCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaitingDeviceView extends StatelessWidget {
  const _WaitingDeviceView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: EmptyState(
        icon: Icons.router_outlined,
        title: 'Menunggu koneksi ke perangkat.',
        message: 'Belum ada data dari ESP32. Pastikan alat menyala dan '
            'terhubung ke Wi-Fi sekolah.',
        action: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

/// Ikon notifikasi + badge jumlah belum dibaca.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<MonitoringController, int>((c) => c.unreadCount);
    return IconButton(
      tooltip: 'Notifikasi',
      onPressed: () => NotificationPanelScreen.open(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(
          unread > 0
              ? Icons.notifications_active_outlined
              : Icons.notifications_none_rounded,
        ),
      ),
    );
  }
}
