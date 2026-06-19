import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/geometry.dart';
import 'design_tunables.dart';

/// The zoom that fits the page width into [viewport] (less [padding] on each
/// side), clamped to [kMinZoom]..[kMaxZoom]. Centering and vertical reach are
/// handled by the scroll viewport, so only the scale is returned.
///
/// Returns `1.0` when the usable width (or the content width) is non-positive,
/// so the caller never applies `0`, `NaN`, or `Infinity`.
double fitWidthScale(JetSize content, Size viewport, double padding) {
  final double usable = viewport.width - 2 * padding;
  if (usable <= 0 || content.width <= 0) return 1.0;
  return (usable / content.width).clamp(kMinZoom, kMaxZoom);
}

/// The zoom that fits the whole page (width *and* height) into [viewport] (less
/// [padding] on each side), clamped to [kMinZoom]..[kMaxZoom]. The limiting
/// dimension wins (the smaller of the two ratios).
///
/// Returns `1.0` when any usable dimension (or content dimension) is
/// non-positive.
double fitPageScale(JetSize content, Size viewport, double padding) {
  final double usableW = viewport.width - 2 * padding;
  final double usableH = viewport.height - 2 * padding;
  if (usableW <= 0 ||
      usableH <= 0 ||
      content.width <= 0 ||
      content.height <= 0) {
    return 1.0;
  }
  final double raw =
      math.min(usableW / content.width, usableH / content.height);
  return raw.clamp(kMinZoom, kMaxZoom);
}
