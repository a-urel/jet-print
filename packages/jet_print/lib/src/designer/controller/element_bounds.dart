/// Shared geometry helpers for editing element bounds within a band.
///
/// Element bounds are **band-relative** (origin at the band's content top-left),
/// so every geometry command — create / move / resize / set-geometry — clamps
/// through the one [clampToBand] function here to guarantee containment
/// (FR-010): no element is ever committed off its band or off the page.
library;

import '../../domain/geometry.dart';
import '../../domain/page_format.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../../domain/report_template.dart';

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
JetRect clampToBand(JetRect bounds, ReportBand band, PageFormat page) {
  final double maxWidth = bandContentWidth(page);
  final double maxHeight = band.height;
  final double width = _clampDouble(bounds.width, 0, maxWidth);
  final double height = _clampDouble(bounds.height, 0, maxHeight);
  final double x = _clampDouble(bounds.x, 0, maxWidth - width);
  final double y = _clampDouble(bounds.y, 0, maxHeight - height);
  return JetRect(x: x, y: y, width: width, height: height);
}

/// Returns a copy of [template] with the bounds of the elements named in
/// [newBounds] replaced (via `withBounds`). Bands that contain no changed
/// element are reused referentially, and so is the whole template when nothing
/// actually changes — preserving FR-025 non-destructiveness. Bounds in
/// [newBounds] are assumed already clamped by the caller.
ReportTemplate replaceElementBounds(
  ReportTemplate template,
  Map<String, JetRect> newBounds,
) {
  if (newBounds.isEmpty) return template;
  bool anyBandChanged = false;
  final List<ReportBand> bands = <ReportBand>[
    for (final ReportBand band in template.bands)
      _replaceInBand(band, newBounds, () => anyBandChanged = true),
  ];
  return anyBandChanged ? template.copyWith(bands: bands) : template;
}

ReportBand _replaceInBand(
  ReportBand band,
  Map<String, JetRect> newBounds,
  void Function() markChanged,
) {
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
  if (!bandChanged) return band;
  markChanged();
  return band.copyWith(elements: elements);
}
