/// Pure measurement helpers shared by the rulers.
///
/// A **display-only** projection of the model's point-based geometry into
/// millimetres (FR-005): the report model is untouched — these convert numbers
/// for the rulers' labels and extent highlight only. Pure Dart (plus the domain
/// geometry value types); no Flutter, no rendering, no serialization — so the
/// projection is unit-testable and carries no view coupling.
library;

import 'dart:math' as math;

import '../../domain/geometry.dart';
import '../controller/selection.dart';
import 'design_time_layout.dart';

/// Points per millimetre: `72 / 25.4` (72 dpi over 25.4 mm-per-inch). The single
/// conversion constant the rulers calibrate against.
const double kPointsPerMm = 72 / 25.4;

/// Converts a length in PDF points to millimetres (display-only, FR-005).
double pointsToMm(double points) => points / kPointsPerMm;

/// Converts a length in millimetres to PDF points.
double mmToPoints(double mm) => mm * kPointsPerMm;

/// The page-absolute bounding rect the rulers highlight for [selection], or
/// `null` when there is nothing to span (FR-012, research D6):
///
/// * a single element → that element's rect;
/// * multiple elements → their **union** (min-left/top → max-right/bottom) as
///   one combined rect — order-independent;
/// * a band → the band's rect;
/// * the report or an empty selection → `null`.
///
/// Pure geometry over the already-built [layout], so it tracks moves/resizes for
/// free (the caller recomputes it per build).
JetRect? selectionExtent(DesignTimeLayout layout, Selection selection) {
  if (selection.isReport) return null;
  if (selection.bandIndex case final int index) return layout.bandRect(index);

  final List<JetRect> rects = <JetRect>[
    for (final String id in selection.ids)
      if (layout.elementRect(id) case final JetRect rect) rect,
  ];
  if (rects.isEmpty) return null;
  if (rects.length == 1) return rects.first; // exact — no float drift from a sum

  double minX = rects.first.x;
  double minY = rects.first.y;
  double maxX = rects.first.x + rects.first.width;
  double maxY = rects.first.y + rects.first.height;
  for (final JetRect rect in rects.skip(1)) {
    minX = math.min(minX, rect.x);
    minY = math.min(minY, rect.y);
    maxX = math.max(maxX, rect.x + rect.width);
    maxY = math.max(maxY, rect.y + rect.height);
  }
  return JetRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY);
}
