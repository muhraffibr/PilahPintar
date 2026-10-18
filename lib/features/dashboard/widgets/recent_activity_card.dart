import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../state/monitoring_controller.dart';
import '../../../widgets/common.dart';
import '../../../widgets/state_views.dart';
import '../../../widgets/status_ui.dart';

/// Aktivitas terbaru: hasil pemilahan + peringatan sistem (PRD §5F).
class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final entries = c.recentActivities();

    if (entries.isEmpty) {
      return const AppCard(
        child: EmptyState(
          compact: true,
          icon: Icons.history_toggle_off_rounded,
          title: 'Belum ada aktivitas.',
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(),
            ActivityTile(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final category = entry.category;
    final avatar = entry.kind == ActivityKind.sorted && category != null
        ? CategoryAvatar(category: category, size: 32)
        : ToneAvatar(icon: entry.kind.icon, tone: entry.kind.tone, size: 32);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: Fmt.time(entry.time),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabularFigures,
                    color: p.inkPrimary,
                  ),
                ),
                TextSpan(text: ' — ', style: TextStyle(color: p.inkMuted)),
                TextSpan(text: entry.message),
              ]),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
