/// The render output IR (spec 011): a lazily-paginated [RenderedReport] of
/// [RenderedPage]s over the existing backend-agnostic `PageFrame` primitives,
/// plus the merged render diagnostics. The input to the on-screen preview and,
/// later, to an export backend (FR-020) — no rework needed there.
library;

import '../fill/report_diagnostics.dart';
import '../frame/page_frame.dart';
import '../text/font_registry.dart';

/// One paginated unit of a [RenderedReport]: the zero-based page [index] and
/// the page's positioned-primitive [frame].
///
/// A thin wrapper over the shared `PageFrame` — the identical frame type the
/// designer paints, so previewing a page is WYSIWYG by construction
/// (Constitution IV) and an export backend can consume it unchanged.
class RenderedPage {
  /// Creates a rendered page.
  const RenderedPage({required this.index, required this.frame});

  /// The zero-based page index within the report.
  final int index;

  /// The page's display list: positioned, backend-agnostic primitives
  /// (including repeated page chrome with resolved `PAGE_NUMBER`/`PAGE_COUNT`).
  final PageFrame frame;
}

/// The result of `JetReportEngine.render`: an exact [pageCount], lazily-built
/// pages via [pageAt], and the merged render [diagnostics] (FR-013).
///
/// Pages are built **on demand** and cached (FR-021): requesting the first
/// page never constructs frames for the others, and re-requesting a page
/// returns the identical cached instance (determinism, SC-004). [pageCount]
/// is exact up front — it is resolved by a cheap boundary-only pagination
/// pass that finds page breaks without building paint primitives.
class RenderedReport {
  /// Creates a rendered report over [pageCount] pages whose frames are
  /// produced on demand by [buildFrame], surfacing the diagnostics of
  /// [diagnosticsSources] merged in order. [title] carries the source
  /// template's name (for display, e.g. the preview toolbar); it defaults to
  /// empty.
  RenderedReport({
    required this.pageCount,
    required PageFrame Function(int index) buildFrame,
    required List<ReportDiagnostics> diagnosticsSources,
    this.title = '',
    FontRegistry? fonts,
  })  : _buildFrame = buildFrame,
        _sources = List<ReportDiagnostics>.unmodifiable(diagnosticsSources),
        fonts = fonts ?? (FontRegistry()..registerDefault());

  /// The total number of pages, exact from the moment of rendering.
  final int pageCount;

  /// The rendered template's name, for display (may be empty).
  final String title;

  /// The font registry this report was measured with (022 — INTERNAL).
  ///
  /// `JetReportEngine.render` builds one registry (the bundled defaults plus
  /// any `RenderOptions.fonts`) and attaches it here, so the preview, the
  /// PDF/PNG exporter, and the printer paint and embed from the **same** bytes
  /// layout was measured with — they read this instead of building a parallel
  /// default-only registry (Principle IV). [FontRegistry] is unexported, so
  /// this is not part of the public API; constructed directly it defaults to a
  /// bundled-default-only registry (today's behavior).
  final FontRegistry fonts;

  final PageFrame Function(int index) _buildFrame;
  final List<ReportDiagnostics> _sources;
  final Map<int, RenderedPage> _cache = <int, RenderedPage>{};

  /// The non-fatal issues collected while rendering, merged across the fill
  /// and layout passes in pass order (FR-013).
  ///
  /// Rendering never throws on malformed data — an unknown field, a missing
  /// parameter, an unresolvable image, or an empty dataset each best-effort
  /// renders and records a [Diagnostic] here instead (FR-014).
  ReportDiagnostics get diagnostics {
    final ReportDiagnostics merged = ReportDiagnostics();
    for (final ReportDiagnostics source in _sources) {
      for (final Diagnostic entry in source.entries) {
        merged.add(entry);
      }
    }
    return merged;
  }

  /// The page at [index] (in `[0, pageCount)`), building its frame on first
  /// access and returning the identical cached page thereafter (FR-021).
  RenderedPage pageAt(int index) {
    if (index < 0 || index >= pageCount) {
      throw RangeError.range(index, 0, pageCount - 1, 'index');
    }
    return _cache.putIfAbsent(
      index,
      () => RenderedPage(index: index, frame: _buildFrame(index)),
    );
  }
}
