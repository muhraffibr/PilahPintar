import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/system_command.dart';
import '../../../state/monitoring_controller.dart';
import '../../../widgets/common.dart';
import '../../../widgets/confirm_dialog.dart';

/// Tombol START/STOP dengan konfirmasi (PRD §5B & §11).
class SystemControlCard extends StatelessWidget {
  const SystemControlCard({super.key});

  Future<void> _confirmAndSend(BuildContext context, SystemCommand command) async {
    final isStart = command == SystemCommand.start;
    final confirmed = await showConfirmDialog(
      context,
      title: isStart ? 'Jalankan sistem?' : 'Hentikan sistem?',
      message: isStart
          ? 'Konveyor akan mulai berjalan dan sistem mulai memilah sampah. '
              'Pastikan tidak ada benda asing di jalur konveyor.'
          : 'Apakah Anda yakin ingin menghentikan sistem? Konveyor akan '
              'berhenti dan sampah tidak dipilah sampai sistem dijalankan '
              'kembali.',
      confirmLabel: isStart ? 'Ya, jalankan' : 'Ya, hentikan',
      icon: isStart ? Icons.play_circle_outline_rounded : Icons.stop_circle_outlined,
      confirmColor: isStart ? ActionColors.start : ActionColors.stop,
    );
    if (!confirmed || !context.mounted) return;

    final controller = context.read<MonitoringController>();
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await controller.sendCommand(command);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(outcome.message),
        backgroundColor: outcome.success ? null : StatusColors.critical,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final p = context.palette;

    ButtonStyle style(Color color) => FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.track,
          disabledForegroundColor: p.inkMuted,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            fontSize: 14,
          ),
        );

    final start = FilledButton.icon(
      style: style(ActionColors.start),
      onPressed:
          c.canStart ? () => _confirmAndSend(context, SystemCommand.start) : null,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('START SYSTEM'),
    );
    final stop = FilledButton.icon(
      style: style(ActionColors.stop),
      onPressed:
          c.canStop ? () => _confirmAndSend(context, SystemCommand.stop) : null,
      icon: const Icon(Icons.stop_rounded),
      label: const Text('STOP SYSTEM'),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 330) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [start, const SizedBox(height: 10), stop],
              );
            }
            return Row(
              children: [
                Expanded(child: start),
                const SizedBox(width: 12),
                Expanded(child: stop),
              ],
            );
          }),
          const SizedBox(height: 12),
          const _CommandStatusLine(),
        ],
      ),
    );
  }
}

class _CommandStatusLine extends StatelessWidget {
  const _CommandStatusLine();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);
    final p = context.palette;
    final command = c.activeCommand?.code ?? '';

    final (Widget leading, String text, Color color) = switch (c.commandPhase) {
      CommandPhase.sending => (
          const _Spinner(),
          'Mengirim perintah $command ke server…',
          p.inkSecondary,
        ),
      CommandPhase.awaitingDevice => (
          const _Spinner(),
          'Menunggu konfirmasi perangkat (ESP32 → STM32)…',
          p.inkSecondary,
        ),
      CommandPhase.failed => (
          const Icon(Icons.error_outline_rounded,
              size: 18, color: StatusColors.critical),
          c.commandError ?? 'Perintah gagal.',
          p.inkPrimary,
        ),
      CommandPhase.idle when !c.deviceOnline => (
          Icon(Icons.link_off_rounded, size: 18, color: p.inkMuted),
          'Menunggu koneksi ke perangkat. Kontrol dinonaktifkan sementara.',
          p.inkSecondary,
        ),
      CommandPhase.idle => (
          Icon(Icons.info_outline_rounded, size: 18, color: p.inkMuted),
          'Perintah dikirim melalui Firebase → ESP32 → STM32 (konveyor).',
          p.inkSecondary,
        ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: leading),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ),
        if (c.commandPhase == CommandPhase.failed)
          InkWell(
            onTap: c.dismissCommandError,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 18, color: p.inkMuted),
            ),
          ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
