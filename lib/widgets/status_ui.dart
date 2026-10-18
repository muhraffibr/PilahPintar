import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/app_notification.dart';
import '../models/waste_bin.dart';
import '../state/monitoring_controller.dart';

/// Pemetaan state → nada warna + ikon. Warna status tidak pernah dipakai
/// sendirian: selalu bersama ikon dan label.
extension BinLevelUi on BinLevel {
  StatusTone get tone => switch (this) {
        BinLevel.normal => StatusTone.good,
        BinLevel.almostFull => StatusTone.warning,
        BinLevel.full => StatusTone.critical,
      };

  IconData get icon => switch (this) {
        BinLevel.normal => Icons.check_circle_rounded,
        BinLevel.almostFull => Icons.warning_amber_rounded,
        BinLevel.full => Icons.error_rounded,
      };
}

extension NotificationTypeUi on NotificationType {
  StatusTone get tone => switch (this) {
        NotificationType.almostFull => StatusTone.warning,
        NotificationType.full => StatusTone.critical,
        NotificationType.connectionLost => StatusTone.critical,
        NotificationType.abnormalStop => StatusTone.critical,
        NotificationType.info => StatusTone.neutral,
      };

  IconData get icon => switch (this) {
        NotificationType.almostFull => Icons.warning_amber_rounded,
        NotificationType.full => Icons.delete_forever_rounded,
        NotificationType.connectionLost => Icons.wifi_off_rounded,
        NotificationType.abnormalStop => Icons.report_problem_rounded,
        NotificationType.info => Icons.info_outline_rounded,
      };
}

extension ActivityKindUi on ActivityKind {
  StatusTone get tone => switch (this) {
        ActivityKind.sorted => StatusTone.good,
        ActivityKind.sortFailed => StatusTone.serious,
        ActivityKind.almostFull => StatusTone.warning,
        ActivityKind.full => StatusTone.critical,
        ActivityKind.connection => StatusTone.critical,
        ActivityKind.error => StatusTone.critical,
        ActivityKind.info => StatusTone.neutral,
      };

  IconData get icon => switch (this) {
        ActivityKind.sorted => Icons.check_rounded,
        ActivityKind.sortFailed => Icons.close_rounded,
        ActivityKind.almostFull => Icons.warning_amber_rounded,
        ActivityKind.full => Icons.delete_forever_rounded,
        ActivityKind.connection => Icons.wifi_off_rounded,
        ActivityKind.error => Icons.report_problem_rounded,
        ActivityKind.info => Icons.info_outline_rounded,
      };
}

extension StatusToneUi on StatusTone {
  IconData get icon => switch (this) {
        StatusTone.good => Icons.check_circle_rounded,
        StatusTone.warning => Icons.warning_amber_rounded,
        StatusTone.serious => Icons.error_outline_rounded,
        StatusTone.critical => Icons.error_rounded,
        StatusTone.neutral => Icons.remove_circle_outline_rounded,
      };
}
