import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/mock/mock_trash_repository.dart';
import '../../models/app_settings.dart';
import '../../state/monitoring_controller.dart';
import '../../widgets/common.dart';

/// Pengaturan: notifikasi & threshold, info sistem, info aplikasi (PRD §7).
/// Tidak ada login/logout/profil — sesuai PRD.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<MonitoringController>().repository;
    return Scaffold(
      appBar: AppBar(titleSpacing: 20, title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ResponsiveBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'Notification Settings',
                  subtitle: 'Berlaku untuk semua perangkat yang memakai aplikasi',
                ),
                const _NotificationSettingsCard(),
                const SectionHeader(title: 'System Settings'),
                const _SystemInfoCard(),
                if (repo is MockTrashRepository) ...[
                  const SectionHeader(
                    title: 'Mode Simulasi',
                    subtitle: 'Hanya tampil saat memakai mock data — untuk demo',
                  ),
                  _SimulationCard(repo: repo),
                ],
                const SectionHeader(title: 'Application Information'),
                const _AppInfoCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationSettingsCard extends StatefulWidget {
  const _NotificationSettingsCard();

  @override
  State<_NotificationSettingsCard> createState() =>
      _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<_NotificationSettingsCard> {
  double? _almostDraft;
  double? _fullDraft;

  Future<void> _commit(MonitoringController c, AppSettings base) async {
    final next = base.copyWith(
      almostFullThreshold: (_almostDraft ?? base.almostFullThreshold).round(),
      fullThreshold: (_fullDraft ?? base.fullThreshold).round(),
    );
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _almostDraft = null;
      _fullDraft = null;
    });
    if (next == base) return;
    try {
      await c.updateSettings(next);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Threshold disimpan: hampir penuh '
              '${next.almostFullThreshold}%, penuh ${next.fullThreshold}%.'),
        ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);
    final s = c.settings;
    final almost = _almostDraft ?? s.almostFullThreshold.toDouble();
    final full = _fullDraft ?? s.fullThreshold.toDouble();
    const gap = AppSettings.minGap;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notifikasi push'),
            subtitle: const Text(
              'Peringatan kapasitas, koneksi, dan gangguan sistem. '
              'Saat nonaktif, peringatan tetap tercatat di panel notifikasi.',
            ),
            value: s.notificationEnabled,
            onChanged: (v) => c.updateSettings(s.copyWith(notificationEnabled: v)),
          ),
          const Divider(),
          const SizedBox(height: 12),
          _ThresholdSlider(
            title: 'Almost Full Threshold',
            subtitle: 'Status "Hampir Penuh" mulai dari nilai ini',
            tone: StatusTone.warning,
            value: almost,
            min: AppSettings.minAlmostFull.toDouble(),
            max: (AppSettings.maxFull - gap).toDouble(),
            onChanged: (v) => setState(() {
              _almostDraft = v;
              if (full < v + gap) _fullDraft = v + gap;
            }),
            onChangeEnd: (_) => _commit(c, s),
          ),
          const SizedBox(height: 16),
          _ThresholdSlider(
            title: 'Full Threshold',
            subtitle: 'Status "Penuh" mulai dari nilai ini',
            tone: StatusTone.critical,
            value: full,
            min: (AppSettings.minAlmostFull + gap).toDouble(),
            max: AppSettings.maxFull.toDouble(),
            onChanged: (v) => setState(() {
              _fullDraft = v;
              if (almost > v - gap) {
                _almostDraft = math.max(AppSettings.minAlmostFull.toDouble(), v - gap);
              }
            }),
            onChangeEnd: (_) => _commit(c, s),
          ),
          const SizedBox(height: 16),
          _ThresholdPreview(almost: almost.round(), full: full.round()),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: s.almostFullThreshold == AppSettings.defaultAlmostFull &&
                      s.fullThreshold == AppSettings.defaultFull
                  ? null
                  : () {
                      _almostDraft = AppSettings.defaultAlmostFull.toDouble();
                      _fullDraft = AppSettings.defaultFull.toDouble();
                      _commit(c, s);
                    },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text(
                'Kembalikan ke default (${AppSettings.defaultAlmostFull}% / '
                '${AppSettings.defaultFull}%)',
              ),
            ),
          ),
          Text(
            'Contoh: "Tempat sampah Logam hampir penuh — kapasitas 82%."',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final String subtitle;
  final StatusTone tone;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StatusDot(tone: tone),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.baseline),
              ),
              child: Text(
                '${value.round()}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: (max - min).round(),
          label: '${value.round()}%',
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _ThresholdPreview extends StatelessWidget {
  const _ThresholdPreview({required this.almost, required this.full});

  final int almost;
  final int full;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusPill(label: 'Normal < $almost%', tone: StatusTone.good),
        StatusPill(
          label: 'Hampir penuh $almost–${full - 1}%',
          tone: StatusTone.warning,
        ),
        StatusPill(label: 'Penuh ≥ $full%', tone: StatusTone.critical),
      ],
    );
  }
}

class _SystemInfoCard extends StatelessWidget {
  const _SystemInfoCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final s = c.system;
    final online = c.deviceOnline;

    Widget pill(String label, StatusTone tone) => StatusPill(label: label, tone: tone);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          InfoRow(
            icon: Icons.power_settings_new_rounded,
            label: 'System status',
            valueWidget: s == null
                ? null
                : pill(s.isOn ? 'ON' : 'OFF',
                    s.isOn ? StatusTone.good : StatusTone.neutral),
          ),
          InfoRow(
            icon: Icons.conveyor_belt,
            label: 'Conveyor status',
            valueWidget: s == null
                ? null
                : pill(
                    s.conveyorRunning ? 'RUNNING' : 'STOPPED',
                    s.conveyorRunning
                        ? StatusTone.good
                        : (s.hasError ? StatusTone.critical : StatusTone.neutral),
                  ),
          ),
          InfoRow(
            icon: online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            label: 'Device connection',
            valueWidget: pill(
              online ? 'Connected' : 'Disconnected',
              online ? StatusTone.good : StatusTone.critical,
            ),
          ),
          InfoRow(
            icon: Icons.sensors_rounded,
            label: 'Data terakhir dari perangkat',
            value: Fmt.lastUpdate(c.lastDeviceUpdate),
          ),
          InfoRow(
            icon: Icons.sync_rounded,
            label: 'Last data synchronization',
            value: Fmt.lastUpdate(c.lastSync),
          ),
          InfoRow(
            icon: Icons.storage_rounded,
            label: 'Sumber data',
            value: c.dataSourceLabel,
          ),
        ],
      ),
    );
  }
}

class _SimulationCard extends StatefulWidget {
  const _SimulationCard({required this.repo});

  final MockTrashRepository repo;

  @override
  State<_SimulationCard> createState() => _SimulationCardState();
}

class _SimulationCardState extends State<_SimulationCard> {
  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Perangkat mengirim data'),
            subtitle: const Text(
              'Matikan untuk mensimulasikan ESP32 terputus. Aplikasi '
              'mendeteksi offline ±15 detik kemudian (heartbeat berhenti).',
            ),
            value: repo.deviceOnline,
            onChanged: (v) {
              setState(() => repo.setDeviceOnline(v));
              _snack(v
                  ? 'Perangkat tersambung kembali.'
                  : 'Heartbeat dihentikan — menunggu deteksi offline…');
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              repo.simulateConveyorFault();
              _snack('Gangguan konveyor disimulasikan.');
            },
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('Simulasikan gangguan konveyor'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              repo.emptyAllBins();
              _snack('Semua tempat sampah dikosongkan.');
            },
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Kosongkan semua tempat sampah'),
          ),
          const SizedBox(height: 8),
          Text(
            'Kapasitas tiap tempat sampah juga bisa diubah dari detail kartu '
            'di Dashboard (Isi +10% / Kosongkan).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _AppInfoCard extends StatelessWidget {
  const _AppInfoCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          InfoRow(label: 'Nama aplikasi', value: AppConfig.appName),
          InfoRow(
            label: 'Versi aplikasi',
            value: '${AppConfig.appVersion} (build ${AppConfig.buildNumber})',
          ),
          InfoRow(label: 'Sekolah', value: AppConfig.schoolName),
          InfoRow(label: 'Informasi proyek', value: AppConfig.projectDescription),
          InfoRow(label: 'Perangkat keras', value: AppConfig.hardwareSummary),
          InfoRow(label: 'Teknologi', value: AppConfig.techSummary),
        ],
      ),
    );
  }
}
