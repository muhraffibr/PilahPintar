import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../state/monitoring_controller.dart';

/// Banner Offline / Error di atas Dashboard (PRD §10 & §13).
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final state = c.overallState;

    final (IconData icon, String title, String message, Widget? action) =
        switch (state) {
      OverallState.offline => (
          Icons.cloud_off_rounded,
          'Offline — Last update: ${Fmt.lastUpdate(c.lastDeviceUpdate)}',
          c.offlineReason == OfflineReason.phoneOffline
              ? 'Ponsel tidak terhubung ke server. Nilai di bawah adalah data '
                  'terakhir, bukan data real-time.'
              : 'Sistem pemilah tidak mengirimkan data. Nilai di bawah adalah '
                  'data terakhir, bukan data real-time.',
          null,
        ),
      OverallState.error when c.streamError != null => (
          Icons.sync_problem_rounded,
          'Error komunikasi',
          c.streamError!,
          TextButton(onPressed: c.retry, child: const Text('Coba lagi')),
        ),
      OverallState.error => (
          Icons.report_problem_rounded,
          'Error — sistem berhenti tidak normal',
          '${c.system?.errorMessage ?? 'Terjadi gangguan pada perangkat'}. '
              'Periksa alat, lalu tekan START SYSTEM untuk menjalankan ulang.',
          null,
        ),
      _ => (Icons.info_outline, '', '', null),
    };

    if (title.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: StatusColors.critical.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: StatusColors.critical.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: StatusColors.critical, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: p.inkSecondary),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
