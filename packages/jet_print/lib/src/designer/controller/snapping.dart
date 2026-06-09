/// Pure snapping geometry: aligns moving/resizing edges to grid, siblings, and
/// band bounds, producing on-screen guide lines.
///
/// Headless and band-relative. The canvas converts the screen-pixel snap
/// threshold to points (via the live zoom) and passes it in, so this stays
/// scale-agnostic (FR-011 / SC-004).
library;

import '../../domain/geometry.dart';
import '../canvas/resize_handle.dart';

/// The orientation of a snap guide line.
enum SnapAxis {
  /// A vertical line at a constant x (an x-edge aligned).
  vertical,

  /// A horizontal line at a constant y (a y-edge aligned).
  horizontal,
}

/// A transient guide line drawn while snapping (band-relative [position]).
class SnapGuide {
  /// Creates a guide on [axis] at [position] (band-relative points).
  const SnapGuide(this.axis, this.position);

  /// The guide orientation.
  final SnapAxis axis;

  /// The band-relative coordinate (x for [SnapAxis.vertical], y otherwise).
  final double position;

  @override
  bool operator ==(Object other) =>
      other is SnapGuide && other.axis == axis && other.position == position;

  @override
  int get hashCode => Object.hash(axis, position);

  @override
  String toString() => 'SnapGuide(${axis.name}, $position)';
}

/// The outcome of a snap: the adjusted [rect] and the [guides] that fired.
class SnapResult {
  /// Creates a result.
  const SnapResult(this.rect, this.guides);

  /// The snapped rectangle (band-relative).
  final JetRect rect;

  /// The guide lines that aligned (empty when nothing snapped).
  final List<SnapGuide> guides;
}

/// A candidate snap line plus, when active, the realized adjustment.
typedef _Best = ({double adjust, double position});

_Best? _nearest(
  Iterable<double> movingEdges,
  List<double> candidates,
  double threshold,
) {
  double bestDist = threshold;
  _Best? best;
  for (final double edge in movingEdges) {
    for (final double candidate in candidates) {
      final double dist = (candidate - edge).abs();
      if (dist <= bestDist) {
        bestDist = dist;
        best = (adjust: candidate - edge, position: candidate);
      }
    }
  }
  return best;
}

List<double> _xCandidates(
  List<JetRect> siblings,
  double contentWidth,
  bool grid,
  double gridStep,
  List<double> gridSeeds,
) =>
    <double>[
      0,
      contentWidth,
      for (final JetRect s in siblings) ...<double>[
        s.x,
        s.x + s.width / 2,
        s.x + s.width,
      ],
      if (grid)
        for (final double seed in gridSeeds) (seed / gridStep).round() * gridStep,
    ];

List<double> _yCandidates(
  List<JetRect> siblings,
  double bandHeight,
  bool grid,
  double gridStep,
  List<double> gridSeeds,
) =>
    <double>[
      0,
      bandHeight,
      for (final JetRect s in siblings) ...<double>[
        s.y,
        s.y + s.height / 2,
        s.y + s.height,
      ],
      if (grid)
        for (final double seed in gridSeeds) (seed / gridStep).round() * gridStep,
    ];

/// Snaps a translated [moving] rect by aligning any of its left/center/right and
/// top/center/bottom edges to the nearest candidate within [threshold].
SnapResult snapMove(
  JetRect moving, {
  required List<JetRect> siblings,
  required JetRect bandBox,
  required bool grid,
  required double gridStep,
  required double threshold,
}) {
  final double left = moving.x;
  final double cx = moving.x + moving.width / 2;
  final double rightE = moving.x + moving.width;
  final double top = moving.y;
  final double cy = moving.y + moving.height / 2;
  final double bottomE = moving.y + moving.height;

  final _Best? bx = _nearest(
      <double>[left, cx, rightE],
      _xCandidates(siblings, bandBox.width, grid, gridStep,
          <double>[left, cx, rightE]),
      threshold);
  final _Best? by = _nearest(
      <double>[top, cy, bottomE],
      _yCandidates(siblings, bandBox.height, grid, gridStep,
          <double>[top, cy, bottomE]),
      threshold);

  final List<SnapGuide> guides = <SnapGuide>[];
  double dx = 0;
  double dy = 0;
  if (bx != null) {
    dx = bx.adjust;
    guides.add(SnapGuide(SnapAxis.vertical, bx.position));
  }
  if (by != null) {
    dy = by.adjust;
    guides.add(SnapGuide(SnapAxis.horizontal, by.position));
  }
  return SnapResult(
    JetRect(x: moving.x + dx, y: moving.y + dy, width: moving.width, height: moving.height),
    guides,
  );
}

/// Snaps a resized [moving] rect by aligning only the edge(s) [handle] dragged.
SnapResult snapResize(
  JetRect moving,
  ResizeHandle handle, {
  required List<JetRect> siblings,
  required JetRect bandBox,
  required bool grid,
  required double gridStep,
  required double threshold,
}) {
  double left = moving.x;
  double right = moving.x + moving.width;
  double top = moving.y;
  double bottom = moving.y + moving.height;
  final List<SnapGuide> guides = <SnapGuide>[];

  if (handle.movesLeft) {
    final _Best? b = _nearest(
        <double>[left],
        _xCandidates(siblings, bandBox.width, grid, gridStep, <double>[left]),
        threshold);
    if (b != null && right - (left + b.adjust) >= 4) {
      left += b.adjust;
      guides.add(SnapGuide(SnapAxis.vertical, b.position));
    }
  } else if (handle.movesRight) {
    final _Best? b = _nearest(
        <double>[right],
        _xCandidates(siblings, bandBox.width, grid, gridStep, <double>[right]),
        threshold);
    if (b != null && (right + b.adjust) - left >= 4) {
      right += b.adjust;
      guides.add(SnapGuide(SnapAxis.vertical, b.position));
    }
  }
  if (handle.movesTop) {
    final _Best? b = _nearest(
        <double>[top],
        _yCandidates(siblings, bandBox.height, grid, gridStep, <double>[top]),
        threshold);
    if (b != null && bottom - (top + b.adjust) >= 4) {
      top += b.adjust;
      guides.add(SnapGuide(SnapAxis.horizontal, b.position));
    }
  } else if (handle.movesBottom) {
    final _Best? b = _nearest(
        <double>[bottom],
        _yCandidates(siblings, bandBox.height, grid, gridStep, <double>[bottom]),
        threshold);
    if (b != null && (bottom + b.adjust) - top >= 4) {
      bottom += b.adjust;
      guides.add(SnapGuide(SnapAxis.horizontal, b.position));
    }
  }

  return SnapResult(
    JetRect(x: left, y: top, width: right - left, height: bottom - top),
    guides,
  );
}
