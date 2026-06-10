// First-page rendering budget (011 — contract C4 / SC-009 / FR-021).
//
// The BINDING assertion is structural: for a large dataset, building the first
// page constructs exactly one page's worth of paint primitives, and that count
// is independent of the total record/page count. Wall-clock is measured and
// logged as ADVISORY ONLY (no hard `< 2 s` gate — CI hosts are too variable;
// the structural assertion is what guarantees first-page time cannot scale
// with dataset size).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_renderer.dart';
import 'package:jet_print/src/rendering/elements/element_renderer_registry.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';

class _EmitCounter {
  int emits = 0;
}

class _SpyRenderer extends ElementRenderer<ReportElement> {
  _SpyRenderer(this._inner, this._counter);

  final ElementRenderer<ReportElement> _inner;
  final _EmitCounter _counter;

  @override
  JetSize measure(ReportElement element, RenderContext ctx, JetConstraints c) =>
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

ReportTemplate _template() => const ReportTemplate(
      name: 'big',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'name',
              bounds: JetRect(x: 0, y: 0, width: 240, height: 16),
              text: 'name',
              expression: r'$F{name}',
            ),
            TextElement(
              id: 'amount',
              bounds: JetRect(x: 260, y: 0, width: 120, height: 16),
              text: 'amount',
              expression: r'$F{amount}',
            ),
          ],
        ),
      ],
    );

JetInMemoryDataSource _source(int records) => JetInMemoryDataSource(
      <Map<String, Object?>>[
        for (int i = 0; i < records; i++)
          <String, Object?>{'name': 'record $i', 'amount': i * 1.5},
      ],
    );

/// Emits exactly one page's primitives for [records] records and returns the
/// emit count after building only page 0.
int _firstPageEmits(int records) {
  final _EmitCounter counter = _EmitCounter();
  final FillResult fill = ReportFiller().fill(_template(), _source(records));
  final LazyLayout lazy = ReportLayouter(renderers: _SpyRegistry(counter))
      .layoutLazy(_template(), fill.report);
  expect(counter.emits, 0,
      reason: 'the boundary-only pass must not construct paint primitives');
  expect(lazy.pageCount, greaterThan(1));
  lazy.buildPage(0);
  return counter.emits;
}

void main() {
  test(
      'first-page frame construction is independent of total record count '
      '(structural SC-009 binding)', () {
    final int smallRun = _firstPageEmits(100);
    final int largeRun = _firstPageEmits(1000);
    expect(smallRun, greaterThan(0));
    expect(largeRun, smallRun,
        reason: 'pageAt(0) must construct exactly one page\'s frame — the '
            'emit count cannot scale with the dataset/page count');
  });

  test('advisory: 1,000-record first page wall-clock (logged, not gated)', () {
    final Stopwatch watch = Stopwatch()..start();
    final RenderedReport report =
        const JetReportEngine().render(_template(), _source(1000));
    final int pageCount = report.pageCount;
    report.pageAt(0);
    watch.stop();
    // Advisory measurement against SC-009's reference-desktop 2 s budget.
    // ignore: avoid_print
    print('[advisory][SC-009] 1,000 records: first page viewable in '
        '${watch.elapsedMilliseconds} ms across $pageCount pages');
    expect(report.pageAt(0).frame.primitives, isNotEmpty);
  });
}
