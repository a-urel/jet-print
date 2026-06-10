/// The Layout engine (spec 008a/008c): places a resolved [FilledReport] band
/// stream onto pages with repeating page chrome, producing one [PageFrame] per
/// page. Geometry plus page-scoped chrome substitution (008c — `PAGE_NUMBER`/
/// `PAGE_COUNT`/params); no image byte-resolution. INTERNAL; the public surface
/// is the 011 JetReportEngine.
///
/// 011 adds the **lazy page-production seam**: [ReportLayouter.layoutLazy]
/// runs the existing measurement + pagination logic as a cheap boundary-only
/// pass (page breaks + page count, **no** paint primitives), and the returned
/// [LazyLayout] constructs each page's frame on demand. The eager
/// [ReportLayouter.layout] is preserved as a thin wrapper over the seam, so
/// the two paths are the same code and stay byte-identical (Constitution IV).
library;

import '../../domain/elements/image_element.dart';
import '../../domain/elements/image_source.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/geometry.dart';
import '../../domain/page_format.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../../domain/report_group.dart';
import '../../domain/report_template.dart';
import '../../expression/expression.dart';
import '../../expression/expression_exception.dart';
import '../../expression/function_registry.dart';
import '../../expression/functions/built_in_functions.dart';
import '../../expression/value.dart';
import '../elements/built_in_element_renderers.dart';
import '../elements/element_renderer_registry.dart';
import '../elements/element_type_registry.dart';
import '../elements/render_context.dart';
import '../fill/filled_report.dart';
import '../fill/page_variables.dart';
import '../fill/report_diagnostics.dart';
import '../frame/frame_builder.dart';
import '../frame/page_frame.dart';
import '../text/font_registry.dart';
import '../text/metrics_text_measurer.dart';
import '../text/text_measurer.dart';
import 'band_measurer.dart';
import 'page_eval_context.dart';

/// One open group instance during pagination: its [name], nesting [level]
/// (outermost = 0), the [headers] measured at its open (for reprint), and its
/// [reprint] flag (008b).
typedef _OpenGroup = ({
  String name,
  int level,
  List<MeasuredBand> headers,
  bool reprint,
});

/// One open group span during the extent pre-pass: its [name], nesting [level]
/// (outermost = 0), and the stream index [openIndex] of its opening header
/// (008b §6.1).
typedef _Span = ({String name, int level, int openIndex});

/// One body-band placement decided by the boundary pass: the measured [band]
/// at page-absolute [y]. Frame construction replays these on demand.
typedef _PlacedBand = ({MeasuredBand band, double y});

/// The result of a layout: the paginated [pages] and collected [diagnostics].
class LayoutResult {
  /// Creates a layout result.
  const LayoutResult({required this.pages, required this.diagnostics});

  /// One frame per page, in order.
  final List<PageFrame> pages;

  /// The non-fatal issues collected during the pass.
  final ReportDiagnostics diagnostics;
}

/// The lazy page-production seam (011 — FR-021): page boundaries and
/// [pageCount] are already resolved (boundary-only pass, no paint
/// primitives); [buildPage] constructs one page's [PageFrame] on demand by
/// replaying that page's recorded placements through the unchanged renderer
/// `emit` path and substituting its page chrome.
///
/// INTERNAL — consumers reach this via `JetReportEngine.render`, whose
/// `RenderedReport` adds per-page caching on top.
class LazyLayout {
  LazyLayout._({
    required PageFormat page,
    required List<List<_PlacedBand>> plans,
    required this.diagnostics,
    required ElementRendererRegistry renderers,
    required RenderContext ctx,
    required JetFunctionRegistry functions,
    required List<ReportBand> headers,
    required List<ReportBand> footers,
    required Map<String, Expression> chromeExprs,
    required Set<String> chromeParseFailed,
    required Set<String> chromeFlagged,
    required Map<String, JetValue> params,
    required double left,
    required double top,
    required double bodyBottom,
  })  : _page = page,
        _plans = plans,
        _renderers = renderers,
        _ctx = ctx,
        _functions = functions,
        _headers = headers,
        _footers = footers,
        _chromeExprs = chromeExprs,
        _chromeParseFailed = chromeParseFailed,
        _chromeFlagged = chromeFlagged,
        _params = params,
        _left = left,
        _top = top,
        _bodyBottom = bodyBottom;

  final PageFormat _page;
  final List<List<_PlacedBand>> _plans;
  final ElementRendererRegistry _renderers;
  final RenderContext _ctx;
  final JetFunctionRegistry _functions;
  final List<ReportBand> _headers;
  final List<ReportBand> _footers;
  final Map<String, Expression> _chromeExprs;
  final Set<String> _chromeParseFailed;
  final Set<String> _chromeFlagged;
  final Map<String, JetValue> _params;
  final double _left;
  final double _top;
  final double _bodyBottom;

  /// Chrome expressions already diagnosed at runtime, deduped across every
  /// page build regardless of build order.
  final Set<String> _runtimeDiagnosed = <String>{};

  /// The non-fatal issues collected so far: the boundary pass's diagnostics,
  /// plus any chrome runtime-evaluation errors appended as pages build.
  final ReportDiagnostics diagnostics;

  /// The total page count, exact from the boundary-only pass.
  int get pageCount => _plans.length;

  /// Translates band-local boxes to the page and emits each element's
  /// primitives — the unchanged 008a placement path, replayed on demand.
  void _place(List<({ReportElement element, JetRect bounds})> boxes,
      double topY, FrameBuilder fb) {
    for (final ({ReportElement element, JetRect bounds}) e in boxes) {
      _renderers.rendererFor(e.element).emit(
            e.element,
            _ctx,
            JetRect(
              x: _left + e.bounds.x,
              y: topY + e.bounds.y,
              width: e.bounds.width,
              height: e.bounds.height,
            ),
            fb,
          );
    }
  }

  /// Per-page chrome substitution (008c). Render follows null-propagation:
  /// a bare unavailable ref is JetNull -> blank; consumed by an operator/
  /// function it poisons to JetError -> '!ERR' (jetStringify of JetError).
  ReportElement _substitute(ReportElement el, int pageNumber) {
    if (el is! TextElement || el.expression == null) return el;
    if (_chromeParseFailed.contains(el.id)) {
      return TextElement(
          id: el.id, bounds: el.bounds, text: '!ERR', style: el.style);
    }
    final Expression? expr = _chromeExprs[el.id];
    if (expr == null) {
      // Unreachable: the pre-pass files every chrome text expression under
      // chromeExprs or chromeParseFailed. Surface a pre/post-pass drift loudly
      // (visible '!ERR' + diagnostic) instead of silently rendering authored
      // text.
      diagnostics.error(
          'internal: no compiled chrome expression for "${el.id}"',
          elementId: el.id);
      return TextElement(
          id: el.id, bounds: el.bounds, text: '!ERR', style: el.style);
    }
    final JetValue value = expr.evaluate(PageEvalContext(
      pageNumber: pageNumber,
      pageCount: pageCount,
      params: _params,
      functions: _functions,
    ));
    if (value is JetError && !_chromeFlagged.contains(el.id)) {
      if (_runtimeDiagnosed.add('${el.id} ${value.message}')) {
        diagnostics.error(
            'chrome text on "${el.id}" failed to evaluate: ${value.message}',
            elementId: el.id);
      }
    }
    return TextElement(
        id: el.id,
        bounds: el.bounds,
        text: jetStringify(value),
        style: el.style);
  }

  /// Builds page [index]'s frame: the boundary pass's body placements in
  /// order, then the page header/footer chrome with this page's substitution —
  /// the identical primitive order the eager pass produced before 011.
  PageFrame buildPage(int index) {
    if (index < 0 || index >= pageCount) {
      throw RangeError.range(index, 0, pageCount - 1, 'index');
    }
    final FrameBuilder fb = FrameBuilder(_page);
    for (final _PlacedBand placed in _plans[index]) {
      _place(placed.band.elements, placed.y, fb);
    }
    final int pageNumber = index + 1;
    double y = _top;
    for (final ReportBand h in _headers) {
      _place(<({ReportElement element, JetRect bounds})>[
        for (final ReportElement el in h.elements)
          (element: _substitute(el, pageNumber), bounds: el.bounds),
      ], y, fb);
      y += h.height;
    }
    y = _bodyBottom;
    for (final ReportBand f in _footers) {
      _place(<({ReportElement element, JetRect bounds})>[
        for (final ReportElement el in f.elements)
          (element: _substitute(el, pageNumber), bounds: el.bounds),
      ], y, fb);
      y += f.height;
    }
    return fb.build();
  }
}

/// Lays a [FilledReport] out onto pages (spec 008a).
class ReportLayouter {
  /// Creates a layouter; [renderers], [measurer], and [functions] default to the
  /// built-ins.
  ReportLayouter({
    ElementRendererRegistry? renderers,
    TextMeasurer? measurer,
    JetFunctionRegistry? functions,
  })  : _renderers = renderers ?? _defaultRenderers(),
        _measurer =
            measurer ?? MetricsTextMeasurer(FontRegistry()..registerDefault()),
        _functions = functions ?? _defaultFunctions();

  final ElementRendererRegistry _renderers;
  final TextMeasurer _measurer;
  final JetFunctionRegistry _functions;

  // Built-ins flow through the canonical PAIRED registration path; the layouter's
  // dependency stays renderer-only (like ReportFiller's JetFunctionRegistry).
  static ElementRendererRegistry _defaultRenderers() {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    return reg.renderers;
  }

  static JetFunctionRegistry _defaultFunctions() {
    final JetFunctionRegistry r = JetFunctionRegistry();
    registerBuiltInFunctions(r);
    return r;
  }

  /// Lays [filled] out eagerly, sourcing page chrome + page format from
  /// [template]. A thin wrapper over [layoutLazy] (011): identical placement,
  /// identical frames — only the driving loop differs (build-all here,
  /// on-demand there).
  LayoutResult layout(ReportTemplate template, FilledReport filled) {
    final LazyLayout lazy = layoutLazy(template, filled);
    return LayoutResult(
      pages: <PageFrame>[
        for (int i = 0; i < lazy.pageCount; i++) lazy.buildPage(i),
      ],
      diagnostics: lazy.diagnostics,
    );
  }

  /// Runs the boundary-only pass over [filled] (011 — FR-021): measures bands,
  /// decides every page break, and records per-page placements **without**
  /// constructing paint primitives. The returned [LazyLayout] knows the exact
  /// page count and builds any page's frame on demand.
  LazyLayout layoutLazy(ReportTemplate template, FilledReport filled) {
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

    // Compile-and-classify chrome text expressions ONCE (008c §5). Parsing and
    // static reference analysis surface page-independent diagnostics here; the
    // per-page build evaluates on demand. Images keep the 008a placeholder info.
    final Map<String, Expression> chromeExprs = <String, Expression>{};
    final Set<String> chromeParseFailed = <String>{};
    final Set<String> chromeFlagged = <String>{};
    for (final ReportBand band in <ReportBand>[...headers, ...footers]) {
      for (final ReportElement el in band.elements) {
        if (el is TextElement && el.expression != null) {
          final Expression expr;
          try {
            expr = Expression.parse(el.expression!);
          } on ExpressionException catch (e) {
            diagnostics.error(
                'chrome text on "${el.id}" failed to parse: ${e.message}',
                elementId: el.id);
            chromeParseFailed.add(el.id);
            chromeFlagged.add(el.id);
            continue;
          }
          chromeExprs[el.id] = expr;
          final ({
            Set<String> fields,
            Set<String> params,
            Set<String> variables
          }) refs = expr.references;
          if (refs.fields.isNotEmpty) {
            diagnostics.warning(
                'chrome text on "${el.id}" references field(s) '
                '${(refs.fields.toList()..sort()).join(', ')}, which have no '
                'data row at page scope',
                elementId: el.id);
            chromeFlagged.add(el.id);
          }
          final List<String> nonPageVars = refs.variables
              .where((String v) => !kPageScopedVariables.contains(v))
              .toList()
            ..sort();
          if (nonPageVars.isNotEmpty) {
            diagnostics.warning(
                'chrome text on "${el.id}" references non-page variable(s) '
                '${nonPageVars.join(', ')}, unavailable at page scope',
                elementId: el.id);
            chromeFlagged.add(el.id);
          }
        } else if (el is ImageElement && el.source is! BytesImageSource) {
          diagnostics.info(
              'chrome image on "${el.id}" is not embedded; renders a placeholder',
              elementId: el.id);
        }
      }
    }

    // Group lookup: name -> nesting level (outermost = 0) and name -> definition.
    final Map<String, int> levelOf = <String, int>{
      for (int i = 0; i < template.groups.length; i++)
        template.groups[i].name: i,
    };
    final Map<String, ReportGroup> groupByName = <String, ReportGroup>{
      for (final ReportGroup g in template.groups) g.name: g,
    };

    // Advisory: a flag on a group with no AUTHORED group-header band does
    // nothing. Keyed off the template (static structure), NOT filled.bands —
    // empty-data reports emit only noData, with no group bands, so a filled scan
    // would falsely fire for every flagged group on empty input.
    final Set<String> groupsWithHeader = <String>{
      for (final ReportBand b in template.bands)
        if (b.type == BandType.groupHeader && b.group != null) b.group!,
    };
    for (final ReportGroup g in template.groups) {
      if ((g.keepTogether || g.reprintHeaderOnEachPage) &&
          !groupsWithHeader.contains(g.name)) {
        diagnostics.info(
            'group "${g.name}" sets keepTogether/reprintHeaderOnEachPage but '
            'has no group-header band; the flag has no effect');
      }
    }

    // Pre-measure every body band once (pure, position-independent).
    final List<MeasuredBand> measured = <MeasuredBand>[
      for (final FilledBand b in filled.bands) bandMeasurer.measure(b),
    ];

    // Prefix sums + single O(n) exit-driven extent pre-pass for keepTogether
    // groups (spec §6.1). keepExtent[openIndex] = the instance's total height.
    // The span lifetime here mirrors the main loop's prevHeaderGroup logic —
    // intentional duplication that keeps the extent a single O(n) pass instead
    // of threading spans through the placement loop.
    final List<double> cum = <double>[0];
    for (final MeasuredBand mb in measured) {
      cum.add(cum.last + mb.height);
    }
    final Map<int, double> keepExtent = <int, double>{};
    final List<_Span> spanStack = <_Span>[];
    void finalizeSpan(_Span s, int exitIndex) {
      if (groupByName[s.name]!.keepTogether) {
        keepExtent[s.openIndex] = cum[exitIndex] - cum[s.openIndex];
      }
    }

    String? spanPrevHeader;
    for (int k = 0; k < filled.bands.length; k++) {
      final FilledBand band = filled.bands[k];
      final bool isGroupBand = (band.type == BandType.groupHeader ||
              band.type == BandType.groupFooter) &&
          band.group != null &&
          levelOf.containsKey(band.group);
      final int level = isGroupBand ? levelOf[band.group]! : -1;
      final bool newHeader = band.type == BandType.groupHeader &&
          isGroupBand &&
          spanPrevHeader != band.group;
      if (newHeader) {
        while (spanStack.isNotEmpty && spanStack.last.level >= level) {
          finalizeSpan(spanStack.removeLast(), k);
        }
      } else if (band.type == BandType.groupFooter && isGroupBand) {
        while (spanStack.isNotEmpty && spanStack.last.level > level) {
          finalizeSpan(spanStack.removeLast(), k);
        }
      } else if (band.type == BandType.summary ||
          band.type == BandType.noData) {
        while (spanStack.isNotEmpty) {
          finalizeSpan(spanStack.removeLast(), k);
        }
      }
      if (newHeader) {
        spanStack.add((name: band.group!, level: level, openIndex: k));
      }
      spanPrevHeader = (band.type == BandType.groupHeader && isGroupBand)
          ? band.group
          : null;
    }
    while (spanStack.isNotEmpty) {
      finalizeSpan(spanStack.removeLast(), filled.bands.length);
    }

    // The boundary pass proper: the unchanged pagination loop, except each
    // decision RECORDS a placement instead of emitting primitives (011). Frame
    // construction replays the recorded placements per page on demand.
    final List<_OpenGroup> openStack = <_OpenGroup>[];
    final List<List<_PlacedBand>> plans = <List<_PlacedBand>>[<_PlacedBand>[]];
    double cursorY = bodyTop;

    void reEmitHeaders() {
      for (final _OpenGroup g in openStack) {
        if (!g.reprint) continue;
        for (final MeasuredBand hmb in g.headers) {
          plans.last.add((band: hmb, y: cursorY));
          cursorY += hmb.height;
        }
      }
    }

    void breakPage() {
      plans.add(<_PlacedBand>[]);
      cursorY = bodyTop;
      reEmitHeaders();
    }

    String? prevHeaderGroup;
    for (int i = 0; i < filled.bands.length; i++) {
      final FilledBand band = filled.bands[i];
      final MeasuredBand mb = measured[i];
      final bool isGroupBand = (band.type == BandType.groupHeader ||
              band.type == BandType.groupFooter) &&
          band.group != null &&
          levelOf.containsKey(band.group);
      final int level = isGroupBand ? levelOf[band.group]! : -1;

      // Pre-place closure (§5.2): an outer footer ends its inner groups (rule 1);
      // summary/noData end all groups (rule 3).
      if (band.type == BandType.groupFooter && isGroupBand) {
        while (openStack.isNotEmpty && openStack.last.level > level) {
          openStack.removeLast();
        }
      } else if (band.type == BandType.summary ||
          band.type == BandType.noData) {
        openStack.clear();
      }

      bool broke = false;
      if (keepExtent.containsKey(i)) {
        final double extent = keepExtent[i]!;
        double repeatedOuter = 0;
        for (final _OpenGroup g in openStack) {
          if (!g.reprint) continue;
          for (final MeasuredBand hmb in g.headers) {
            repeatedOuter += hmb.height;
          }
        }
        final double fresh = bodyCapacity - repeatedOuter;
        if (extent <= fresh &&
            cursorY + extent > bodyBottom &&
            cursorY > bodyTop) {
          breakPage();
          broke = true;
        }
      }
      if (!broke && cursorY + mb.height > bodyBottom && cursorY > bodyTop) {
        breakPage();
      }
      if (bodyCapacity > 0 && mb.height > bodyCapacity) {
        diagnostics.warning('band height ${mb.height} exceeds body capacity '
            '$bodyCapacity; content overflows');
      }
      plans.last.add((band: mb, y: cursorY));
      cursorY += mb.height;

      // Post-place lifetime (§5.1 open/append; §5.2 rule 2 footer-run end).
      if (band.type == BandType.groupHeader && isGroupBand) {
        if (prevHeaderGroup == band.group &&
            openStack.isNotEmpty &&
            openStack.last.name == band.group) {
          openStack.last.headers.add(mb); // continuation header
        } else {
          while (openStack.isNotEmpty && openStack.last.level >= level) {
            openStack.removeLast(); // new instance: close prior g + inner
          }
          openStack.add((
            name: band.group!,
            level: level,
            headers: <MeasuredBand>[mb],
            reprint: groupByName[band.group]!.reprintHeaderOnEachPage,
          ));
        }
      } else if (band.type == BandType.groupFooter && isGroupBand) {
        final bool runEnd = i + 1 >= filled.bands.length ||
            filled.bands[i + 1].type != BandType.groupFooter ||
            filled.bands[i + 1].group != band.group;
        if (runEnd) {
          while (openStack.isNotEmpty && openStack.last.level >= level) {
            openStack.removeLast();
          }
        }
      }
      prevHeaderGroup = (band.type == BandType.groupHeader && isGroupBand)
          ? band.group
          : null;
    }

    return LazyLayout._(
      page: page,
      plans: plans,
      diagnostics: diagnostics,
      renderers: _renderers,
      ctx: ctx,
      functions: _functions,
      headers: headers,
      footers: footers,
      chromeExprs: chromeExprs,
      chromeParseFailed: chromeParseFailed,
      chromeFlagged: chromeFlagged,
      params: filled.params,
      left: left,
      top: top,
      bodyBottom: bodyBottom,
    );
  }
}
