import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../common.dart';

/// Sumbu-Y "rapi": interval 1/2/5 × 10ⁿ dengan ±4 garis bantu.
({double max, double interval}) niceAxis(num maxValue, {int ticks = 4}) {
  if (maxValue <= 0) return (max: ticks.toDouble(), interval: 1);
  final raw = maxValue / ticks;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final residual = raw / magnitude;
  final step = residual <= 1
      ? 1
      : residual <= 2
          ? 2
          : residual <= 5
              ? 5
              : 10;
  final interval = math.max(1.0, step * magnitude);
  final max = (maxValue / interval).ceil() * interval;
  return (max: max == maxValue ? max + interval : max, interval: interval);
}

TextStyle? axisLabelStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.palette.inkMuted,
          fontFeatures: tabularFigures,
        );
