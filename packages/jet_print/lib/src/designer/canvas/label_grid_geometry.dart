/// Design-time geometry of a label grid's cells, for the canvas cue (spec 035).
///
/// Pure data: given a definition and its [DesignTimeLayout], it produces the
/// first editable cell rect plus the read-only ghost cell rects that cue the
/// repeated grid. The active band's design rect spans the full content width
/// (the canvas does NOT narrow it — element drag/resize stay unchanged, FR-013);
/// this overlay draws a cell at `columnWidth` and `columnCount - 1` ghosts at
/// pitch, clipped to the content's right edge. Nothing here changes layout.
library;

import 'dart:math' as math;

import '../../domain/band.dart';
import '../../domain/column_layout.dart';
import '../../domain/geometry.dart';
import '../../domain/report_definition.dart';
import 'design_time_layout.dart';

/// The first (editable) cell rect plus the read-only ghost cell rects.
typedef LabelGridCue = ({JetRect cell, List<JetRect> ghosts});

/// Computes the [LabelGridCue] for [def]'s active label band, or null when no
/// grid is active — i.e. the body is not a pure single-detail body, the sole
/// detail band has no [ColumnLayout], the layout has a non-positive cell width,
/// or the band has no design rect.
LabelGridCue? labelGridCue(ReportDefinition def, DesignTimeLayout layout) {
  if (!def.isPureSingleDetailBody) return null;
  final Band? band = def.soleDetailBand;
  final ColumnLayout? cl = band?.columnLayout;
  if (band == null || cl == null || cl.columnWidth <= 0) return null;
  final JetRect? rect = layout.bandRect(band.id);
  if (rect == null) return null;

  final double contentRight = rect.x + rect.width;
  final JetRect cell = JetRect(
    x: rect.x,
    y: rect.y,
    width: math.min(cl.columnWidth, rect.width),
    height: rect.height,
  );
  final List<JetRect> ghosts = <JetRect>[];
  final double pitch = cl.columnWidth + cl.columnSpacing;
  for (int i = 1; i < cl.columnCount; i++) {
    final double x = rect.x + i * pitch;
    if (x >= contentRight) break;
    final double w = math.min(cl.columnWidth, contentRight - x);
    if (w <= 0) break;
    ghosts.add(JetRect(x: x, y: rect.y, width: w, height: rect.height));
  }
  return (cell: cell, ghosts: ghosts);
}
