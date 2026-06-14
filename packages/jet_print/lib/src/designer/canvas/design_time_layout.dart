/// The non-paginated, design-time geometry of a definition's bands and elements.
library;

import 'dart:math' as math;

import '../../domain/band.dart';
import '../../domain/detail_scope.dart';
import '../../domain/geometry.dart';
import '../../domain/report_band.dart' show BandType;
import '../../domain/report_definition.dart';

/// One band positioned on the design surface: its stable [id], the [band]
/// itself, and its page-absolute [rect].
typedef PlacedBand = ({String id, Band band, JetRect rect});

/// Computes, once per definition revision, the page-absolute rectangles of every
/// band and element for the **design** view.
///
/// The reified tree (spec 024) is flattened into a single **visual document
/// order** — page header, column header, title, then the scope tree (each
/// scope's group headers, its ordered children recursively, then its group
/// footers innermost-first), then no-data, summary, and the bottom-anchored
/// column/page footers. Flow bands stack downward from the top margin; the
/// column-/page-footer bands are *anchored to the bottom* of the sheet (stacked
/// upward from the bottom margin, preserving order), leaving an empty "flow" gap
/// in between — exactly how a rendered page looks (true WYSIWYG). If the authored
/// bands are taller than the sheet, the surface grows so nothing is clipped.
/// Element bounds are band-relative, so the page-absolute element rect is
/// `(bandLeft + bounds.x, bandTop + bounds.y)` — the same mapping the render-time
/// layouter uses.
class DesignTimeLayout {
  DesignTimeLayout._({
    required this.size,
    required this.bands,
    required Map<String, JetRect> bandRects,
    required Map<String, JetRect> elementRects,
    required Map<String, String> bandOfElement,
  })  : _bandRects = bandRects,
        _elementRects = elementRects,
        _bandOfElement = bandOfElement;

  /// Builds the layout for [definition].
  factory DesignTimeLayout.of(ReportDefinition definition) {
    final double left = definition.page.margins.left;
    final double right = definition.page.margins.right;
    final double top = definition.page.margins.top;
    final double bottom = definition.page.margins.bottom;
    final double contentWidth = definition.page.width - left - right;

    final List<Band> ordered = _orderedBands(definition);

    double topHeight = 0;
    double bottomHeight = 0;
    for (final Band band in ordered) {
      if (isBottomAnchored(band.type)) {
        bottomHeight += band.height;
      } else {
        topHeight += band.height;
      }
    }

    // The surface is the full paper sheet, but never shorter than the authored
    // content (top flow + bottom-anchored bands + margins) so nothing is clipped.
    final double surfaceHeight = math.max(
      definition.page.height,
      top + topHeight + bottomHeight + bottom,
    );

    final Map<String, JetRect> bandRects = <String, JetRect>{};

    // Flow bands stack downward from the top margin.
    double topY = top;
    for (final Band band in ordered) {
      if (isBottomAnchored(band.type)) continue;
      bandRects[band.id] =
          JetRect(x: left, y: topY, width: contentWidth, height: band.height);
      topY += band.height;
    }

    // Footer bands stack upward from the bottom margin, preserving order (so a
    // column footer ends up above the page footer).
    double bottomY = surfaceHeight - bottom;
    for (final Band band in ordered.reversed) {
      if (!isBottomAnchored(band.type)) continue;
      bottomY -= band.height;
      bandRects[band.id] = JetRect(
          x: left, y: bottomY, width: contentWidth, height: band.height);
    }

    final List<PlacedBand> placed = <PlacedBand>[];
    final Map<String, JetRect> elementRects = <String, JetRect>{};
    final Map<String, String> bandOfElement = <String, String>{};
    for (final Band band in ordered) {
      final JetRect r = bandRects[band.id]!;
      placed.add((id: band.id, band: band, rect: r));
      for (final element in band.elements) {
        elementRects[element.id] = JetRect(
          x: r.x + element.bounds.x,
          y: r.y + element.bounds.y,
          width: element.bounds.width,
          height: element.bounds.height,
        );
        bandOfElement[element.id] = band.id;
      }
    }

    return DesignTimeLayout._(
      size: JetSize(definition.page.width, surfaceHeight),
      bands: List<PlacedBand>.unmodifiable(placed),
      bandRects: bandRects,
      elementRects: elementRects,
      bandOfElement: bandOfElement,
    );
  }

  /// Flattens [def] into the visual top-to-bottom band order (see class doc).
  /// The background slot is excluded — it is a reserved layer, not a stacked
  /// band.
  static List<Band> _orderedBands(ReportDefinition def) {
    final List<Band> out = <Band>[];
    void add(Band? b) {
      if (b != null) out.add(b);
    }

    add(def.furniture.pageHeader);
    add(def.furniture.columnHeader);
    add(def.body.title);

    void scope(DetailScope s) {
      for (final g in s.groups) {
        add(g.header);
      }
      for (final ScopeNode n in s.children) {
        switch (n) {
          case BandNode(band: final Band b):
            add(b);
          case NestedScope(scope: final DetailScope inner):
            scope(inner);
        }
      }
      for (final g in s.groups.reversed) {
        add(g.footer);
      }
    }

    scope(def.body.root);

    add(def.body.noData);
    add(def.body.summary);
    add(def.furniture.columnFooter);
    add(def.furniture.pageFooter);
    return out;
  }

  /// Whether a band of [type] is anchored to the bottom of the sheet (printed at
  /// the page bottom) rather than flowing from the top. Bottom-anchored bands
  /// grow upward from their bottom edge, so their resize handle sits on top.
  static bool isBottomAnchored(BandType type) =>
      type == BandType.pageFooter || type == BandType.columnFooter;

  /// The full design-surface extent, in points (page width × stacked height).
  final JetSize size;

  /// Every placed band in visual document order (the order they stack on the
  /// sheet, footers included at their anchored positions).
  final List<PlacedBand> bands;

  final Map<String, JetRect> _bandRects;
  final Map<String, JetRect> _elementRects;
  final Map<String, String> _bandOfElement;

  /// The page-absolute rects of every band, in visual document order — for the
  /// grid + separator chrome painters.
  List<JetRect> get bandRects =>
      <JetRect>[for (final PlacedBand b in bands) b.rect];

  /// The page-absolute rect of the band with stable id [bandId], or null.
  JetRect? bandRect(String bandId) => _bandRects[bandId];

  /// The page-absolute rect of the element with [id], or null if absent.
  JetRect? elementRect(String id) => _elementRects[id];

  /// The stable id of the band owning the element with [id], or null if absent.
  String? bandOfElement(String id) => _bandOfElement[id];

  /// The stable id of the band whose vertical range contains [point]'s `dy`.
  /// When the point lands outside every band — the empty flow gap, or above/below
  /// the sheet — it snaps to the vertically nearest band so a drop always lands
  /// somewhere valid (FR-023 nearest-valid-band). Null only when there are no
  /// bands.
  String? bandIdNear(JetOffset point) {
    if (bands.isEmpty) return null;
    for (final PlacedBand b in bands) {
      if (point.dy >= b.rect.y && point.dy < b.rect.y + b.rect.height) {
        return b.id;
      }
    }
    String nearest = bands.first.id;
    double bestDistance = double.infinity;
    for (final PlacedBand b in bands) {
      final JetRect r = b.rect;
      final double distance = point.dy < r.y
          ? r.y - point.dy
          : (point.dy > r.y + r.height ? point.dy - (r.y + r.height) : 0);
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = b.id;
      }
    }
    return nearest;
  }

  /// The stable id of the band whose rect exactly contains [point], or null when
  /// the point lands in no band (the margins, the empty flow gap, or off the
  /// sheet).
  ///
  /// Unlike [bandIdNear] there is no nearest-band fallback: this drives *click
  /// selection*, where an empty spot must resolve to the report/page — not to a
  /// band the pointer is merely near.
  String? bandIdAt(JetOffset point) {
    for (final PlacedBand b in bands) {
      final JetRect r = b.rect;
      if (point.dx >= r.x &&
          point.dx <= r.x + r.width &&
          point.dy >= r.y &&
          point.dy <= r.y + r.height) {
        return b.id;
      }
    }
    return null;
  }

  /// Converts a page point to a band-relative offset within the band with stable
  /// id [bandId] (origin at the band's content top-left). Returns [page]
  /// unchanged when the band is unknown.
  JetOffset toBandLocal(String bandId, JetOffset page) {
    final JetRect? r = _bandRects[bandId];
    if (r == null) return page;
    return JetOffset(page.dx - r.x, page.dy - r.y);
  }
}
