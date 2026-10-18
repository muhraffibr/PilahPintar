import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/waste_bin.dart';
import '../../../state/monitoring_controller.dart';
import '../../../widgets/common.dart';

/// Kartu besar status sistem: ON/OFF, koneksi, dan konveyor (PRD §5A).
class SystemStatusCard extends StatelessWidget {
  const SystemStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);
    final p = context.palette;
    final s = c.system;
    final stale = !c.deviceOnline;

    final (String headline, StatusTone tone, String caption) =
        switch (c.overallState) {
      OverallState.offline => (
          'OFFLINE',
          StatusTone.critical,
          'Tidak ada data baru dari perangkat sejak '
              '${Fmt.lastUpdate(c.lastDeviceUpdate)}.',
        ),
      OverallState.error => (
          'ERROR',
          StatusTone.critical,
          s?.errorMessage ?? c.streamError ?? 'Terjadi masalah komunikasi.',
        ),
      OverallState.systemOff => (
          'SYSTEM OFF',
          StatusTone.neutral,
          'Sistem tidak sedang berjalan. Tekan START SYSTEM untuk memulai.',
        ),
      OverallState.full => (
          'ONLINE',
          StatusTone.good,
          '${c.countBinsAt(BinLevel.full)} tempat sampah penuh — '
              'segera kosongkan.',
        ),
      OverallState.warning => (
          'ONLINE',
          StatusTone.good,
          '${c.countBinsAt(BinLevel.almostFull)} tempat sampah hampir penuh.',
        ),
      _ => (
          'ONLINE',
          StatusTone.good,
          'Sistem berjalan normal. Semua tempat sampah di bawah ambang batas.',
        ),
    };

    final binSummary = switch (c.overallState) {
      OverallState.full => const StatusPill(label: 'Full', tone: StatusTone.critical),
      OverallState.warning =>
        const StatusPill(label: 'Warning', tone: StatusTone.warning),
      OverallState.online => const StatusPill(label: 'Normal', tone: StatusTone.good),
      _ => null,
    };

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 18, color: p.inkSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'System Status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      theme.textTheme.labelLarge?.copyWith(color: p.inkSecondary),
                ),
              ),
              ?binSummary,
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              StatusDot(tone: tone, size: 14),
              const SizedBox(width: 12),
              Flexible(
                child: Text(headline, style: theme.textTheme.headlineSmall),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(caption, style: theme.textTheme.bodyMedium?.copyWith(color: p.inkSecondary)),
          const SizedBox(height: 14),
          const Divider(),
          _StatusRow(
            icon: Icons.power_settings_new_rounded,
            label: 'Sistem',
            value: s == null ? '—' : (s.isOn ? 'ON' : 'OFF'),
            tone: s?.isOn == true ? StatusTone.good : StatusTone.neutral,
            dimmed: stale,
          ),
          _StatusRow(
            icon: c.deviceOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            label: 'Koneksi',
            value: c.deviceOnline ? 'Connected' : 'Disconnected',
            tone: c.deviceOnline ? StatusTone.good : StatusTone.critical,
          ),
          _StatusRow(
            icon: Icons.conveyor_belt,
            label: 'Konveyor',
            value: s == null ? '—' : (s.conveyorRunning ? 'RUNNING' : 'STOPPED'),
            tone: s == null
                ? StatusTone.neutral
                : s.conveyorRunning
                    ? StatusTone.good
                    : (s.hasError ? StatusTone.critical : StatusTone.neutral),
            dimmed: stale,
          ),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 15, color: p.inkMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Last update: ${Fmt.lastUpdate(c.lastDeviceUpdate)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFeatures: tabularFigures),
                ),
              ),
              Text(
                stale ? 'Nilai terakhir' : (c.isSimulation ? 'Simulasi' : 'Real-time'),
                style: theme.textTheme.bodySmall?.copyWith(color: p.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.dimmed = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final StatusTone tone;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: p.inkSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            StatusDot(tone: tone),
            const SizedBox(width: 8),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(letterSpacing: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
