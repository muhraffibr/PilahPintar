import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/waste_category.dart';
import '../../../state/monitoring_controller.dart';
import '../../../widgets/common.dart';
import '../../../widgets/status_ui.dart';
import 'bin_detail_sheet.dart';

/// Empat kartu kapasitas tempat sampah (PRD §5C).
class BinCapacityGrid extends StatelessWidget {
  const BinCapacityGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600 ? 4 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: WasteCategory.values.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 196 + (textScale - 1) * 64,
        ),
        itemBuilder: (context, i) =>
            BinCapacityCard(category: WasteCategory.values[i]),
      );
    });
  }
}

class BinCapacityCard extends StatelessWidget {
  const BinCapacityCard({super.key, required this.category});

  final WasteCategory category;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);
    final p = context.palette;
    final bin = c.binFor(category);
    final level = c.levelFor(category);
    final stale = !c.deviceOnline;

    return Semantics(
      button: true,
      label: bin == null
          ? 'Tempat sampah ${category.label}, data tidak tersedia'
          : 'Tempat sampah ${category.label}, kapasitas '
              '${Fmt.percent(bin.capacityPercentage)}, ${level!.label}',
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        onTap: () => showBinDetailSheet(context, category),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryAvatar(category: category, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: p.inkMuted),
              ],
            ),
            const Spacer(),
            Center(
              child: Opacity(
                opacity: stale ? 0.5 : 1,
                child: CapacityRing(
                  percent: bin?.capacityPercentage,
                  tone: level?.tone ?? StatusTone.neutral,
                  size: 84,
                ),
              ),
            ),
            const Spacer(),
            if (bin == null || level == null)
              Text('Data unavailable', style: theme.textTheme.bodySmall)
            else ...[
              StatusPill(label: level.label, tone: level.tone),
              if (stale) ...[
                const SizedBox(height: 4),
                Text(
                  'Update ${Fmt.lastUpdate(bin.lastUpdated)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: p.inkMuted),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Indikator melingkar kapasitas; warna mengikuti status (normal/hampir
/// penuh/penuh), angka di tengah memakai warna tinta.
class CapacityRing extends StatelessWidget {
  const CapacityRing({
    super.key,
    required this.percent,
    required this.tone,
    this.size = 84,
    this.strokeWidth = 8,
  });

  final double? percent;
  final StatusTone tone;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    final value = percent;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: (value ?? 0) / 100),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: animated,
                strokeWidth: strokeWidth,
                strokeCap: StrokeCap.round,
                backgroundColor: p.track,
                color: p.tone(tone),
              ),
            ),
            Text(
              value == null ? '—' : Fmt.percent(animated * 100),
              style: (size >= 100
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleLarge)
                  ?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
