/// Shared geometry helpers for editing element bounds within a band.
///
/// Element bounds are **band-relative** (origin at the band's content top-left),
/// so every geometry command — create / move / resize / set-geometry — clamps
/// through the one [clampToBand] function here to guarantee containment
/// (FR-010): no element is ever committed off its band or off the page.
library;

import '../../domain/band.dart';
import '../../domain/geometry.dart';
import '../../domain/page_format.dart';
import '../../domain/report_definition.dart';
import '../../domain/report_element.dart';
import 'band_walker.dart';

/// The usable content width of a page, in points (page width minus L/R margins).
double bandContentWidth(PageFormat page) =>
    page.width - page.margins.left - page.margins.right;

double _clampDouble(double value, double min, double max) {
  if (max < min) return min;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// Clamps [bounds] so the element stays fully inside its [band]'s content box:
/// width within `[0, contentWidth]`, height within `[0, band.height]`, and the
/// top-left positioned so the element does not overflow either edge. Size is
/// clamped first, then position, so an oversized element shrinks to fit rather
/// than being pushed off-screen.
JetRect clampToBand(JetRect bounds, Band band, PageFormat page) {
  final double maxWidth = bandContentWidth(page);
  final double maxHeight = band.height;
  final double width = _clampDouble(bounds.width, 0, maxWidth);
  final double height = _clampDouble(bounds.height, 0, maxHeight);
  final double x = _clampDouble(bounds.x, 0, maxWidth - width);
  final double y = _clampDouble(bounds.y, 0, maxHeight - height);
  return JetRect(x: x, y: y, width: width, height: height);
}

/// Returns a copy of [definition] with the bounds of the elements named in
/// [newBounds] replaced (via `withBounds`). Bands that contain no changed
/// element are reused referentially; an empty [newBounds] returns [definition]
/// unchanged. Bounds in [newBounds] are assumed already clamped by the caller.
///
/// The transform walks the whole reified tree via [mapBands], so an element in
/// any band — furniture, once-band, group header/footer, or a scope's per-row
/// band — is found by id without the caller knowing where it lives.
ReportDefinition replaceElementBoundsInDef(
  ReportDefinition definition,
  Map<String, JetRect> newBounds,
) {
  if (newBounds.isEmpty) return definition;
  return mapBands(definition, (Band band) {
    bool bandChanged = false;
    final List<ReportElement> elements = <ReportElement>[];
    for (final ReportElement element in band.elements) {
      final JetRect? target = newBounds[element.id];
      if (target != null && target != element.bounds) {
        elements.add(element.withBounds(target));
        bandChanged = true;
      } else {
        elements.add(element);
      }
    }
    return bandChanged ? band.copyWith(elements: elements) : band;
  });
}
