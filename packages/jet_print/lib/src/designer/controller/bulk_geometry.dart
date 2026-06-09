/// Pure align/distribute geometry over a multi-selection (FR-012).
///
/// Works in band-relative coordinates. Horizontal alignment/distribution uses
/// `x` (comparable across bands — all share the left-margin origin); vertical
/// uses `y` (meaningful within one band). Returns the new bounds per id; the
/// controller clamps each to its band and commits.
library;

import '../../domain/geometry.dart';

/// How [computeAlign] aligns the selection's edges.
enum AlignKind {
  /// Align left edges to the leftmost.
  left,

  /// Center horizontally on the selection's bounding-box center.
  centerHorizontal,

  /// Align right edges to the rightmost.
  right,

  /// Align top edges to the topmost.
  top,

  /// Center vertically on the selection's bounding-box middle.
  middle,

  /// Align bottom edges to the bottommost.
  bottom,
}

/// The axis [computeDistribute] spaces along.
enum DistributeAxis {
  /// Even horizontal spacing between centers.
  horizontal,

  /// Even vertical spacing between centers.
  vertical,
}

/// An element id paired with its current band-relative bounds.
typedef Positioned = ({String id, JetRect bounds});

/// Returns the new bounds (by id) that align [items] per [kind]. A selection of
/// fewer than two is returned unchanged.
Map<String, JetRect> computeAlign(List<Positioned> items, AlignKind kind) {
  if (items.length < 2) return const <String, JetRect>{};
  double minX = items.first.bounds.x;
  double maxRight = items.first.bounds.x + items.first.bounds.width;
  double minY = items.first.bounds.y;
  double maxBottom = items.first.bounds.y + items.first.bounds.height;
  for (final Positioned p in items) {
    minX = p.bounds.x < minX ? p.bounds.x : minX;
    maxRight = (p.bounds.x + p.bounds.width) > maxRight
        ? p.bounds.x + p.bounds.width
        : maxRight;
    minY = p.bounds.y < minY ? p.bounds.y : minY;
    maxBottom = (p.bounds.y + p.bounds.height) > maxBottom
        ? p.bounds.y + p.bounds.height
        : maxBottom;
  }
  final double cx = (minX + maxRight) / 2;
  final double cy = (minY + maxBottom) / 2;

  final Map<String, JetRect> out = <String, JetRect>{};
  for (final Positioned p in items) {
    final JetRect b = p.bounds;
    final double x = switch (kind) {
      AlignKind.left => minX,
      AlignKind.right => maxRight - b.width,
      AlignKind.centerHorizontal => cx - b.width / 2,
      _ => b.x,
    };
    final double y = switch (kind) {
      AlignKind.top => minY,
      AlignKind.bottom => maxBottom - b.height,
      AlignKind.middle => cy - b.height / 2,
      _ => b.y,
    };
    out[p.id] = JetRect(x: x, y: y, width: b.width, height: b.height);
  }
  return out;
}

/// Returns the new bounds (by id) that distribute [items] evenly by center
/// along [axis]. Fewer than three items are returned unchanged (the endpoints
/// pin the range).
Map<String, JetRect> computeDistribute(
  List<Positioned> items,
  DistributeAxis axis,
) {
  if (items.length < 3) return const <String, JetRect>{};
  final List<Positioned> sorted = List<Positioned>.of(items)
    ..sort((Positioned a, Positioned b) {
      final double ca = axis == DistributeAxis.horizontal
          ? a.bounds.x + a.bounds.width / 2
          : a.bounds.y + a.bounds.height / 2;
      final double cb = axis == DistributeAxis.horizontal
          ? b.bounds.x + b.bounds.width / 2
          : b.bounds.y + b.bounds.height / 2;
      return ca.compareTo(cb);
    });

  double centerOf(Positioned p) => axis == DistributeAxis.horizontal
      ? p.bounds.x + p.bounds.width / 2
      : p.bounds.y + p.bounds.height / 2;

  final double first = centerOf(sorted.first);
  final double last = centerOf(sorted.last);
  final double step = (last - first) / (sorted.length - 1);

  final Map<String, JetRect> out = <String, JetRect>{};
  for (int i = 1; i < sorted.length - 1; i++) {
    final Positioned p = sorted[i];
    final double target = first + step * i;
    final JetRect b = p.bounds;
    out[p.id] = axis == DistributeAxis.horizontal
        ? JetRect(
            x: target - b.width / 2, y: b.y, width: b.width, height: b.height)
        : JetRect(
            x: b.x, y: target - b.height / 2, width: b.width, height: b.height);
  }
  return out;
}
