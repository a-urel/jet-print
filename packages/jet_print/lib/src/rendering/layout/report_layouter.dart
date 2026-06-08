/// The Layout engine (spec 008a): places a resolved [FilledReport] band stream
/// onto pages with repeating page chrome, producing one [PageFrame] per page.
/// Pure geometry — no expression engine, no image byte-resolution. INTERNAL; the
/// public surface is the 011 JetReportEngine.
library;

import '../../domain/elements/image_element.dart';
import '../../domain/elements/image_source.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/geometry.dart';
import '../../domain/page_format.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../../domain/report_template.dart';
import '../elements/built_in_element_renderers.dart';
import '../elements/element_renderer_registry.dart';
import '../elements/element_type_registry.dart';
import '../elements/render_context.dart';
import '../fill/filled_report.dart';
import '../fill/report_diagnostics.dart';
import '../frame/frame_builder.dart';
import '../frame/page_frame.dart';
import '../text/font_registry.dart';
import '../text/metrics_text_measurer.dart';
import '../text/text_measurer.dart';
import 'band_measurer.dart';

/// The result of a layout: the paginated [pages] and collected [diagnostics].
class LayoutResult {
  /// Creates a layout result.
  const LayoutResult({required this.pages, required this.diagnostics});

  /// One frame per page, in order.
  final List<PageFrame> pages;

  /// The non-fatal issues collected during the pass.
  final ReportDiagnostics diagnostics;
}

/// Lays a [FilledReport] out onto pages (spec 008a).
class ReportLayouter {
  /// Creates a layouter; [renderers] and [measurer] default to the built-ins.
  ReportLayouter({ElementRendererRegistry? renderers, TextMeasurer? measurer})
      : _renderers = renderers ?? _defaultRenderers(),
        _measurer =
            measurer ?? MetricsTextMeasurer(FontRegistry()..registerDefault());

  final ElementRendererRegistry _renderers;
  final TextMeasurer _measurer;

  // Built-ins flow through the canonical PAIRED registration path; the layouter's
  // dependency stays renderer-only (like ReportFiller's JetFunctionRegistry).
  static ElementRendererRegistry _defaultRenderers() {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    return reg.renderers;
  }

  /// Lays [filled] out, sourcing page chrome + page format from [template].
  LayoutResult layout(ReportTemplate template, FilledReport filled) {
    final ReportDiagnostics diagnostics = ReportDiagnostics();
    final RenderContext ctx = RenderContext(measurer: _measurer);
    final BandMeasurer bandMeasurer = BandMeasurer(_renderers, ctx);

    // template.page is authoritative for the page format (spec §2/§10 #5).
    final PageFormat page = template.page;
    if (filled.page != page) {
      diagnostics.warning(
          'filled.page differs from template.page; using template.page');
    }

    final double left = page.margins.left;
    final double top = page.margins.top;
    final double bottom = page.height - page.margins.bottom;
    final double contentHeight = bottom - top;

    final List<ReportBand> headers = <ReportBand>[
      for (final ReportBand b in template.bands)
        if (b.type == BandType.pageHeader) b,
    ];
    final List<ReportBand> footers = <ReportBand>[
      for (final ReportBand b in template.bands)
        if (b.type == BandType.pageFooter) b,
    ];
    double sumHeight(List<ReportBand> bands) {
      double h = 0;
      for (final ReportBand b in bands) {
        h += b.height;
      }
      return h;
    }

    final double headerHeight = sumHeight(headers);
    final double footerHeight = sumHeight(footers);
    final double bodyTop = top + headerHeight;
    final double bodyBottom = bottom - footerHeight;
    final double bodyCapacity = bodyBottom - bodyTop;

    if (bodyCapacity <= 0) {
      diagnostics.warning(
          'page chrome (header $headerHeight + footer $footerHeight) leaves no '
          'room for body on a $contentHeight-pt printable height; chrome '
          'overlaps and body bands overflow');
    }

    // Band types 008a does not lay out yet (008b) — flag once each.
    for (final BandType ignored in const <BandType>[
      BandType.columnHeader,
      BandType.columnFooter,
      BandType.background,
    ]) {
      if (template.bands.any((ReportBand b) => b.type == ignored)) {
        diagnostics
            .info('${ignored.name} bands are not laid out in 008a; ignored');
      }
    }

    // Scan chrome ONCE for unresolved bindings (spec §7) — info only; no later
    // owner is named (page-scoped text -> 008c; images -> Fill/paint-prep).
    for (final ReportBand band in <ReportBand>[...headers, ...footers]) {
      for (final ReportElement el in band.elements) {
        if (el is TextElement && el.expression != null) {
          diagnostics.info(
              'chrome text expression on "${el.id}" was not evaluated in the '
              'static layout pass',
              elementId: el.id);
        } else if (el is ImageElement && el.source is! BytesImageSource) {
          diagnostics.info(
              'chrome image on "${el.id}" is not embedded; renders a placeholder',
              elementId: el.id);
        }
      }
    }

    // Translate band-local boxes to the page and emit each element's primitives.
    void place(List<({ReportElement element, JetRect bounds})> boxes,
        double topY, FrameBuilder fb) {
      for (final ({ReportElement element, JetRect bounds}) e in boxes) {
        _renderers.rendererFor(e.element).emit(
              e.element,
              ctx,
              JetRect(
                x: left + e.bounds.x,
                y: topY + e.bounds.y,
                width: e.bounds.width,
                height: e.bounds.height,
              ),
              fb,
            );
      }
    }

    // 1. Body pagination (held builders; always >= 1 page).
    final List<FrameBuilder> pages = <FrameBuilder>[FrameBuilder(page)];
    double cursorY = bodyTop;
    for (final FilledBand band in filled.bands) {
      final MeasuredBand mb = bandMeasurer.measure(band);
      if (cursorY + mb.height > bodyBottom && cursorY > bodyTop) {
        pages.add(FrameBuilder(page));
        cursorY = bodyTop;
      }
      if (bodyCapacity > 0 && mb.height > bodyCapacity) {
        diagnostics.warning('band height ${mb.height} exceeds body capacity '
            '$bodyCapacity; content overflows');
      }
      place(mb.elements, cursorY, pages.last);
      cursorY += mb.height;
    }

    // 2. Chrome post-pass (page count now known; chrome is fixed-height, emitted
    // at authored bounds). This is the seam 008c reuses for page-number
    // substitution.
    for (final FrameBuilder fb in pages) {
      double y = top;
      for (final ReportBand h in headers) {
        place(_authoredBoxes(h), y, fb);
        y += h.height;
      }
      y = bodyBottom;
      for (final ReportBand f in footers) {
        place(_authoredBoxes(f), y, fb);
        y += f.height;
      }
    }

    return LayoutResult(
      pages: <PageFrame>[for (final FrameBuilder fb in pages) fb.build()],
      diagnostics: diagnostics,
    );
  }

  // Chrome elements emit at their authored band-local box (no growth).
  List<({ReportElement element, JetRect bounds})> _authoredBoxes(
          ReportBand band) =>
      <({ReportElement element, JetRect bounds})>[
        for (final ReportElement el in band.elements)
          (element: el, bounds: el.bounds),
      ];
}
