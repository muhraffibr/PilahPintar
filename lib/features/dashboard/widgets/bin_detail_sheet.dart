import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/mock/mock_trash_repository.dart';
import '../../../models/app_settings.dart';
import '../../../models/waste_category.dart';
import '../../../state/monitoring_controller.dart';
import '../../../widgets/common.dart';
import '../../../widgets/status_ui.dart';
import 'bin_capacity_grid.dart';

/// Detail kategori → status kapasitas (PRD §17 flow monitoring).
Future<void> showBinDetailSheet(BuildContext context, WasteCategory category) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BinDetailSheet(category: category),
  );
}

class _BinDetailSheet extends StatelessWidget {
  const _BinDetailSheet({required this.category});

  final WasteCategory category;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);
    final p = context.palette;
    final bin = c.binFor(category);
    final level = c.levelFor(category);
    final settings = c.settings;
    final todayCount = c.todayCounts[category] ?? 0;
    final repo = c.repository;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryAvatar(category: category, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tempat Sampah ${category.label}',
                          style: theme.textTheme.titleLarge),
                      Text(category.examples.join(' · '),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CapacityRing(
                  percent: bin?.capacityPercentage,
                  tone: level?.tone ?? StatusTone.neutral,
                  size: 112,
                  strokeWidth: 10,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status kapasitas', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      if (level != null)
                        StatusPill(label: level.label, tone: level.tone)
                      else
                        Text('Data unavailable', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 10),
                      Text(
                        c.deviceOnline
                            ? 'Real-time · ${Fmt.lastUpdate(bin?.lastUpdated)}'
                            : 'Offline · Last update: '
                                '${Fmt.lastUpdate(bin?.lastUpdated)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontFeatures: tabularFigures),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (bin != null)
              ThresholdBar(percent: bin.capacityPercentage, settings: settings),
            const SizedBox(height: 12),
            const Divider(),
            InfoRow(
              icon: Icons.inventory_2_outlined,
              label: 'Dipilah hari ini',
              value: '${Fmt.number(todayCount)} item',
            ),
            InfoRow(
              icon: Icons.tune_rounded,
              label: 'Ambang batas',
              value: 'Hampir penuh ≥ ${settings.almostFullThreshold}% · '
                  'Penuh ≥ ${settings.fullThreshold}%',
            ),
            const InfoRow(
              icon: Icons.sensors_rounded,
              label: 'Sensor',
              value: 'Ultrasonik (jarak → % kapasitas)',
            ),
            if (repo is MockTrashRepository) ...[
              const Divider(),
              const SizedBox(height: 12),
              Text('Simulasi', style: theme.textTheme.labelLarge?.copyWith(color: p.inkSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => repo.addCapacity(category, 10),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Isi +10%'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => repo.emptyBin(category),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Kosongkan'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Batang 0–100% dengan zona Normal / Hampir penuh / Penuh dan penanda nilai.
class ThresholdBar extends StatelessWidget {
  const ThresholdBar({super.key, required this.percent, required this.settings});

  final double percent;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    final almost = settings.almostFullThreshold.toDouble();
    final full = settings.fullThreshold.toDouble();
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: p.inkSecondary,
      fontFeatures: tabularFigures,
    );

    Widget zone(double width, StatusTone tone, BorderRadius radius) {
      if (width <= 0) return const SizedBox.shrink();
      return Expanded(
        flex: (width * 10).round(),
        child: Container(
          decoration: BoxDecoration(
            color: p.tone(tone).withValues(alpha: 0.22),
            borderRadius: radius,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final x = percent.clamp(0.0, 100.0) / 100 * w;
          return SizedBox(
            height: 22,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: 6,
                  bottom: 6,
                  child: Row(
                    children: [
                      zone(almost, StatusTone.good,
                          const BorderRadius.horizontal(left: Radius.circular(5))),
                      const SizedBox(width: 2),
                      zone(full - almost, StatusTone.warning, BorderRadius.zero),
                      const SizedBox(width: 2),
                      zone(100 - full, StatusTone.critical,
                          const BorderRadius.horizontal(right: Radius.circular(5))),
                    ],
                  ),
                ),
                Positioned(
                  left: (x - 2).clamp(0.0, w - 4).toDouble(),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: p.inkPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('0%', style: labelStyle),
            Expanded(
              child: Text(
                'Normal · Hampir penuh · Penuh',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            Text('100%', style: labelStyle),
          ],
        ),
      ],
    );
  }
}
