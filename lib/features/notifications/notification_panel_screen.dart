import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_notification.dart';
import '../../state/monitoring_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_ui.dart';

/// Panel notifikasi: lihat peringatan → tandai sudah dibaca (PRD §8 & §17).
class NotificationPanelScreen extends StatefulWidget {
  const NotificationPanelScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationPanelScreen()),
      );

  @override
  State<NotificationPanelScreen> createState() =>
      _NotificationPanelScreenState();
}

class _NotificationPanelScreenState extends State<NotificationPanelScreen> {
  bool _unreadOnly = true;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);
    final all = c.notifications;
    final unread = c.unreadCount;
    final items = _unreadOnly ? all.where((n) => !n.isRead).toList() : all;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          if (unread > 0)
            TextButton.icon(
              onPressed: c.markAllNotificationsRead,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Tandai semua dibaca'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: true, label: Text('Belum dibaca ($unread)')),
                  const ButtonSegment(value: false, label: Text('Semua')),
                ],
                selected: {_unreadOnly},
                onSelectionChanged: (s) => setState(() => _unreadOnly = s.first),
              ),
            ),
            if (!c.settings.notificationEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Notifikasi push dinonaktifkan di Pengaturan. Peringatan tetap '
                  'tercatat di panel ini.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: 'Tidak ada notifikasi baru.',
                      message: _unreadOnly && all.isNotEmpty
                          ? 'Semua peringatan sudah dibaca.'
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _NotificationTile(
                        notification: items[i],
                        onTap: () => c.markNotificationRead(items[i].id),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final n = notification;
    return AppCard(
      onTap: n.isRead ? null : onTap,
      color: n.isRead ? p.surface : p.surfaceMuted,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToneAvatar(icon: n.type.icon, tone: n.type.tone, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.type.title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: p.inkSecondary,
                        ),
                      ),
                    ),
                    Text(
                      Fmt.relative(n.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(color: p.inkMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  n.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      Fmt.lastUpdate(n.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.inkMuted,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const Spacer(),
                    if (!n.isRead)
                      Text(
                        'Ketuk untuk tandai dibaca',
                        style: theme.textTheme.bodySmall?.copyWith(color: p.inkMuted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (!n.isRead) ...[
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: StatusDot(tone: StatusTone.critical, size: 8),
            ),
          ],
        ],
      ),
    );
  }
}
