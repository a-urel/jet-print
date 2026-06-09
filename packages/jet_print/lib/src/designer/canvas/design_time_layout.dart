/// The non-paginated, design-time geometry of a template's bands and elements.
library;

import '../../domain/geometry.dart';
import '../../domain/report_template.dart';

/// Computes, once per template revision, the page-absolute rectangles of every
/// band and element for the **design** view.
///
/// Unlike the render-time layout engine, the design surface is *not* paginated:
/// bands simply stack top-to-bottom from the top margin, each at its designed
/// height, across the page's content width. Element bounds are band-relative
/// (origin at the band's content top-left), so the page-absolute element rect is
/// `(margin.left + bounds.x, bandTop + bounds.y)` — exactly the mapping the
/// render-time layouter uses, which is what keeps the design view WYSIWYG.
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

    final List<JetRect> bandRects = <JetRect>[];
    final Map<String, JetRect> elementRects = <String, JetRect>{};
    final Map<String, int> bandOfElement = <String, int>{};

    double y = top;
    for (int i = 0; i < template.bands.length; i++) {
      final band = template.bands[i];
      bandRects.add(
        JetRect(x: left, y: y, width: contentWidth, height: band.height),
      );
      for (final element in band.elements) {
        elementRects[element.id] = JetRect(
          x: left + element.bounds.x,
          y: y + element.bounds.y,
          width: element.bounds.width,
          height: element.bounds.height,
        );
        bandOfElement[element.id] = i;
      }
      y += band.height;
    }

    return DesignTimeLayout._(
      size: JetSize(template.page.width, y + bottom),
      bandRects: List<JetRect>.unmodifiable(bandRects),
      elementRects: elementRects,
      bandOfElement: bandOfElement,
    );
  }

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

  /// The index of the band whose vertical range contains [point]'s `dy`,
  /// clamped to the first/last band so a drop always lands somewhere valid
  /// (FR-023 nearest-valid-band). Null only when the template has no bands.
  int? bandIndexAt(JetOffset point) {
    if (_bandRects.isEmpty) return null;
    for (int i = 0; i < _bandRects.length; i++) {
      final JetRect r = _bandRects[i];
      if (point.dy >= r.y && point.dy < r.y + r.height) return i;
    }
    // Above the first band -> first; below the last -> last.
    return point.dy < _bandRects.first.y ? 0 : _bandRects.length - 1;
  }

  /// Converts a page point to a band-relative offset within the band at
  /// [bandIndex] (origin at the band's content top-left).
  JetOffset toBandLocal(int bandIndex, JetOffset page) {
    final JetRect r = _bandRects[bandIndex];
    return JetOffset(page.dx - r.x, page.dy - r.y);
  }
}
