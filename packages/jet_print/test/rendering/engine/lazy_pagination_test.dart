// Lazy pagination seam (011 — contracts C4/C5; FR-021).
//
// The binding assertions are STRUCTURAL, not wall-clock: a counting renderer
// registry proves the boundary-only pass emits no paint primitives, and that
// building one page emits exactly that page's primitives. Lazy/eager
// equivalence (`buildPage(i)` byte-identical to `layout().pages[i]`) is the
// guard that the seam reuses the existing pagination logic (Constitution IV).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_renderer.dart';
import 'package:jet_print/src/rendering/elements/element_renderer_registry.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// A small page: 200x100, 10pt margins -> content 180x80; capacity 80 with no
// chrome, so three 30pt bands split 2 + 1 across pages.
const PageFormat _smallPage =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ShapeElement _rect(String id, double height) => ShapeElement(
      id: id,
      bounds: JetRect(x: 0, y: 0, width: 180, height: height),
      kind: ShapeKind.rectangle,
    );

FilledBand _body(double height, {String id = 'r'}) => FilledBand(
      type: BandType.detail,
      height: height,
      elements: <ReportElement>[_rect(id, height)],
      variables: const <String, JetValue>{},
    );

ReportTemplate _tpl({List<ReportBand> bands = const <ReportBand>[]}) =>
    ReportTemplate(name: 'demo', page: _smallPage, bands: bands);

FilledReport _filled(List<FilledBand> bands) =>
    FilledReport(page: _smallPage, bands: bands);

ReportBand _chromeText(BandType type, String id, String expression,
        {double height = 20}) =>
    ReportBand(type: type, height: height, elements: <ReportElement>[
      TextElement(
        id: id,
        bounds: JetRect(x: 0, y: 0, width: 180, height: height),
        text: '',
        expression: expression,
      ),
    ]);

String _textRun(PageFrame page, String id) => page.primitives
    .whereType<TextRunPrimitive>()
    .firstWhere((TextRunPrimitive p) => p.elementId == id)
    .lines
    .map((TextLine l) => l.text)
    .join();

/// Counts every `emit` dispatched through the registry — i.e. every element
/// whose paint primitives are constructed.
class _EmitCounter {
  int emits = 0;
}

class _SpyRenderer extends ElementRenderer<ReportElement> {
  _SpyRenderer(this._inner, this._counter);

  final ElementRenderer<ReportElement> _inner;
  final _EmitCounter _counter;

  @override
  JetSize measure(
          ReportElement element, RenderContext ctx, JetConstraints c) =>
      _inner.measure(element, ctx, c);

  @override
  void emit(ReportElement element, RenderContext ctx, JetRect bounds,
      FrameBuilder out) {
    _counter.emits++;
    _inner.emit(element, ctx, bounds, out);
  }
}

class _SpyRegistry extends ElementRendererRegistry {
  _SpyRegistry(this._counter) : _delegate = _builtIns();

  final ElementRendererRegistry _delegate;
  final _EmitCounter _counter;

  static ElementRendererRegistry _builtIns() {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    return reg.renderers;
  }

  @override
  ElementRenderer<ReportElement> rendererFor(ReportElement element) =>
      _SpyRenderer(_delegate.rendererFor(element), _counter);
}

void main() {
  group('boundary-only pass (C4)', () {
    test('layoutLazy resolves pageCount without emitting any primitive', () {
      final _EmitCounter counter = _EmitCounter();
      final ReportLayouter layouter =
          ReportLayouter(renderers: _SpyRegistry(counter));
      final LazyLayout lazy = layouter.layoutLazy(
        _tpl(),
        _filled(<FilledBand>[_body(30), _body(30), _body(30)]),
      );
      expect(lazy.pageCount, 2, reason: '30+30 fit; the third band breaks');
      expect(counter.emits, 0,
          reason: 'the boundary pass must not construct paint primitives');
    });

    test('buildPage(0) constructs exactly the first page\'s primitives', () {
      final _EmitCounter counter = _EmitCounter();
      final ReportLayouter layouter =
          ReportLayouter(renderers: _SpyRegistry(counter));
      final LazyLayout lazy = layouter.layoutLazy(
        _tpl(),
        _filled(<FilledBand>[_body(30), _body(30), _body(30)]),
      );
      lazy.buildPage(0);
      expect(counter.emits, 2,
          reason: 'page 0 holds two bands of one element each; the third '
              'band\'s frame must not be constructed');
    });
  });

  group('lazy == eager (C5)', () {
    test('each lazily built frame is byte-identical to the eager layout()',
        () {
      // Chrome bands exercise the per-page substitution path too.
      final ReportTemplate template = _tpl(bands: <ReportBand>[
        _chromeText(BandType.pageHeader, 'hd', r'"Report"'),
        _chromeText(BandType.pageFooter, 'pf',
            r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}'),
      ]);
      final List<FilledBand> bands = <FilledBand>[
        for (int i = 0; i < 5; i++) _body(30, id: 'b$i'),
      ];
      final LayoutResult eager =
          ReportLayouter().layout(template, _filled(bands));
      final LazyLayout lazy =
          ReportLayouter().layoutLazy(template, _filled(bands));
      expect(lazy.pageCount, eager.pages.length);
      for (int i = 0; i < lazy.pageCount; i++) {
        expect(lazy.buildPage(i), eager.pages[i],
            reason: 'page $i must be byte-identical lazily and eagerly');
      }
    });

    test('PAGE_COUNT resolves through the lazy seam', () {
      final ReportTemplate template = _tpl(bands: <ReportBand>[
        _chromeText(BandType.pageFooter, 'pf',
            r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}'),
      ]);
      // Footer (20) leaves 60 capacity: 2 x 30pt bands per page, 3 pages.
      final LazyLayout lazy = ReportLayouter().layoutLazy(
        template,
        _filled(<FilledBand>[for (int i = 0; i < 6; i++) _body(30)]),
      );
      expect(lazy.pageCount, 3);
      expect(_textRun(lazy.buildPage(0), 'pf'), 'Page 1 of 3');
      expect(_textRun(lazy.buildPage(2), 'pf'), 'Page 3 of 3');
    });
  });

  group('RenderedReport page-on-demand + cache (C4)', () {
    PageFrame frameFor(int index) =>
        PageFrame(page: _smallPage, primitives: <FramePrimitive>[
          RectPrimitive(
            bounds: const JetRect(x: 0, y: 0, width: 180, height: 10),
            elementId: 'p$index',
          ),
        ]);

    test('pageAt builds on demand, caches, and re-access is identical', () {
      final List<int> built = <int>[];
      final RenderedReport report = RenderedReport(
        pageCount: 3,
        buildFrame: (int i) {
          built.add(i);
          return frameFor(i);
        },
        diagnosticsSources: <ReportDiagnostics>[ReportDiagnostics()],
      );
      expect(built, isEmpty, reason: 'construction must not build any page');
      final RenderedPage p1 = report.pageAt(1);
      expect(built, <int>[1], reason: 'only the requested page is built');
      final RenderedPage again = report.pageAt(1);
      expect(built, <int>[1], reason: 're-access must hit the cache');
      expect(identical(p1.frame, again.frame), isTrue);
      expect(p1.index, 1);
    });

    test('pageAt rejects an out-of-range index', () {
      final RenderedReport report = RenderedReport(
        pageCount: 1,
        buildFrame: frameFor,
        diagnosticsSources: <ReportDiagnostics>[ReportDiagnostics()],
      );
      expect(() => report.pageAt(-1), throwsRangeError);
      expect(() => report.pageAt(1), throwsRangeError);
    });
  });

  group('facade smoke (C4 via render())', () {
    test('render().pageAt(0) yields a viewable first page and exact count',
        () {
      final ReportTemplate template = _tpl(bands: <ReportBand>[
        const ReportBand(
          type: BandType.detail,
          height: 30,
          elements: <ReportElement>[
            TextElement(
              id: 'name',
              bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
              text: 'name',
              expression: r'$F{name}',
            ),
          ],
        ),
      ]);
      final JetInMemoryDataSource source = JetInMemoryDataSource(
        <Map<String, Object?>>[
          for (int i = 0; i < 6; i++) <String, Object?>{'name': 'row $i'},
        ],
      );
      final RenderedReport report =
          const JetReportEngine().render(template, source);
      expect(report.pageCount, 3, reason: '2 x 30pt bands per 80pt page');
      expect(report.pageAt(0).frame.primitives, isNotEmpty);
      expect(_textRun(report.pageAt(0).frame, 'name'), 'row 0');
    });
  });
}
