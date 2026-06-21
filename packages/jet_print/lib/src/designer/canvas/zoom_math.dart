import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/geometry.dart';
import '../controller/view_fit_mode.dart';
import 'design_tunables.dart';

/// Screen width (in logical pixels) at or above which a freshly opened report
/// defaults to 100% (actual size) instead of fitting to width. Matches the
/// toolbar's phone breakpoint (`kBarVeryNarrowWidth`).
const double kDefaultZoomDesktopMinWidth = 600;

/// The built-in default fit for a freshly opened report, by overall screen
/// width: phone-class screens (`< kDefaultZoomDesktopMinWidth`) fit to width so
/// the page is legible; larger screens open at 100% ([JetViewFitMode.none] =
/// actual size). Shared by the designer canvas and the preview.
JetViewFitMode defaultFitForScreenWidth(double screenWidth) =>
    screenWidth < kDefaultZoomDesktopMinWidth
        ? JetViewFitMode.width
        : JetViewFitMode.none;

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
