/// The non-paginated, design-time geometry of a template's bands and elements.
library;

import 'dart:math' as math;

import '../../domain/geometry.dart';
import '../../domain/report_band.dart';
import '../../domain/report_template.dart';

/// Computes, once per template revision, the page-absolute rectangles of every
/// band and element for the **design** view.
///
/// The design surface is a real sheet of paper: it spans the page format's full
/// dimensions ([ReportTemplate.page] width × height). Flow bands (title, page
/// header, detail, groups, …) stack downward from the top margin; the page-/
/// column-footer bands are *anchored to the bottom* of the sheet (stacked upward
/// from the bottom margin, preserving authored order), leaving an empty "flow"
/// gap in between — exactly how a rendered page looks (true WYSIWYG). If the
/// authored bands are taller than the sheet, the surface grows so nothing is
/// clipped. Element bounds are band-relative (origin at the band's content
/// top-left), so the page-absolute element rect is `(bandLeft + bounds.x,
/// bandTop + bounds.y)` — the same mapping the render-time layouter uses.
class DesignTimeLayout {
  DesignTimeLayout._({
    required this.size,
    required List<JetRect> bandRects,
    required Map<String, JetRect> elementRects,
    required Map<String, int> bandOfElement,
  })  : _bandRects = bandRects,
        _elementRects = elementRects,
        _bandOfElement = bandOfElement;

  /// Builds the layout for [template].
  factory DesignTimeLayout.of(ReportTemplate template) {
    final double left = template.page.margins.left;
    final double right = template.page.margins.right;
    final double top = template.page.margins.top;
    final double bottom = template.page.margins.bottom;
    final double contentWidth = template.page.width - left - right;

    double topHeight = 0;
    double bottomHeight = 0;
    for (final ReportBand band in template.bands) {
      if (_isBottomAnchored(band.type)) {
        bottomHeight += band.height;
      } else {
        topHeight += band.height;
      }
    }

    // The surface is the full paper sheet, but never shorter than the authored
    // content (top flow + bottom-anchored bands + margins) so nothing is clipped.
    final double surfaceHeight = math.max(
      template.page.height,
      top + topHeight + bottomHeight + bottom,
    );

    final List<JetRect?> rects =
        List<JetRect?>.filled(template.bands.length, null);

    // Flow bands stack downward from the top margin.
    double topY = top;
    for (int i = 0; i < template.bands.length; i++) {
      final ReportBand band = template.bands[i];
      if (_isBottomAnchored(band.type)) continue;
      rects[i] =
          JetRect(x: left, y: topY, width: contentWidth, height: band.height);
      topY += band.height;
    }

    // Footer bands stack upward from the bottom margin, preserving authored
    // order (so e.g. a column footer ends up above the page footer).
    double bottomY = surfaceHeight - bottom;
    for (int i = template.bands.length - 1; i >= 0; i--) {
      final ReportBand band = template.bands[i];
      if (!_isBottomAnchored(band.type)) continue;
      bottomY -= band.height;
      rects[i] =
          JetRect(x: left, y: bottomY, width: contentWidth, height: band.height);
    }

    final List<JetRect> bandRects = <JetRect>[];
    final Map<String, JetRect> elementRects = <String, JetRect>{};
    final Map<String, int> bandOfElement = <String, int>{};
    for (int i = 0; i < template.bands.length; i++) {
      final JetRect r = rects[i]!;
      bandRects.add(r);
      for (final element in template.bands[i].elements) {
        elementRects[element.id] = JetRect(
          x: r.x + element.bounds.x,
          y: r.y + element.bounds.y,
          width: element.bounds.width,
          height: element.bounds.height,
        );
        bandOfElement[element.id] = i;
      }
    }

    return DesignTimeLayout._(
      size: JetSize(template.page.width, surfaceHeight),
      bandRects: List<JetRect>.unmodifiable(bandRects),
      elementRects: elementRects,
      bandOfElement: bandOfElement,
    );
  }

  /// Whether a band of [type] is anchored to the bottom of the sheet (printed at
  /// the page bottom) rather than flowing from the top.
  static bool _isBottomAnchored(BandType type) =>
      type == BandType.pageFooter || type == BandType.columnFooter;

  /// The full design-surface extent, in points (page width × stacked height).
  final JetSize size;

  final List<JetRect> _bandRects;
  final Map<String, JetRect> _elementRects;
  final Map<String, int> _bandOfElement;

  /// The page-absolute rects of every band, index-aligned with `template.bands`.
  List<JetRect> get bandRects => _bandRects;

  /// The page-absolute rect of the band at [index], or null if out of range.
  JetRect? bandRect(int index) =>
      (index >= 0 && index < _bandRects.length) ? _bandRects[index] : null;

  /// The page-absolute rect of the element with [id], or null if absent.
  JetRect? elementRect(String id) => _elementRects[id];

  /// The index of the band owning the element with [id], or null if absent.
  int? bandOfElement(String id) => _bandOfElement[id];

  /// The index of the band whose vertical range contains [point]'s `dy`. When
  /// the point lands outside every band — the empty flow gap between the last
  /// flow band and the bottom-anchored footers, or above/below the sheet — it
  /// snaps to the vertically nearest band so a drop always lands somewhere valid
  /// (FR-023 nearest-valid-band). Null only when the template has no bands.
  int? bandIndexAt(JetOffset point) {
    if (_bandRects.isEmpty) return null;
    for (int i = 0; i < _bandRects.length; i++) {
      final JetRect r = _bandRects[i];
      if (point.dy >= r.y && point.dy < r.y + r.height) return i;
    }
    int nearest = 0;
    double bestDistance = double.infinity;
    for (int i = 0; i < _bandRects.length; i++) {
      final JetRect r = _bandRects[i];
      final double distance = point.dy < r.y
          ? r.y - point.dy
          : (point.dy > r.y + r.height ? point.dy - (r.y + r.height) : 0);
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = i;
      }
    }
    return nearest;
  }

  /// Converts a page point to a band-relative offset within the band at
  /// [bandIndex] (origin at the band's content top-left).
  JetOffset toBandLocal(int bandIndex, JetOffset page) {
    final JetRect r = _bandRects[bandIndex];
    return JetOffset(page.dx - r.x, page.dy - r.y);
  }
}
