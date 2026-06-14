/// Maps a page point to the element it lands on, respecting z-order.
library;

import '../../domain/geometry.dart';
import 'design_time_layout.dart';

extension _RectHit on JetRect {
  bool containsPoint(JetOffset p, double slop) =>
      p.dx >= x - slop &&
      p.dx <= x + width + slop &&
      p.dy >= y - slop &&
      p.dy <= y + height + slop;
}

/// Returns the id of the top-most element under [pagePoint], or null if none.
///
/// Paint order is the layout's visual band order, then element order within a
/// band; the element drawn **last** is on top, so we scan in reverse and return
/// the first hit. [slop] (in points) enlarges each element's hit area beyond its
/// visual bounds so very thin or tiny elements (e.g. a zero-height line) remain
/// grabbable (FR-009 edge case).
String? hitTestElement(
  DesignTimeLayout layout,
  JetOffset pagePoint, {
  double slop = 0,
}) {
  for (final PlacedBand placed in layout.bands.reversed) {
    final elements = placed.band.elements;
    for (int e = elements.length - 1; e >= 0; e--) {
      final JetRect? rect = layout.elementRect(elements[e].id);
      if (rect != null && rect.containsPoint(pagePoint, slop)) {
        return elements[e].id;
      }
    }
  }
  return null;
}
