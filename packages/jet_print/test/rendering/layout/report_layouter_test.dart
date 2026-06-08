// ReportLayouter: pagination, page chrome, coordinates, diagnostics (008a).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// A small page: 200x100, 10pt margins -> content 180x80; top=10 bottom=90
// left=10 right=190.
const PageFormat _smallPage =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ShapeElement _rect(String id, JetRect bounds) =>
    ShapeElement(id: id, bounds: bounds, kind: ShapeKind.rectangle);

// A body band whose single rectangle fills the band (so its measured height
// equals the designed height — no growth, exact geometry).
FilledBand _body(double height, {String id = 'r'}) => FilledBand(
      type: BandType.detail,
      height: height,
      elements: <ReportElement>[
        _rect(id, JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
      variables: const <String, JetValue>{},
    );

ReportTemplate _tpl({List<ReportBand> bands = const <ReportBand>[]}) =>
    ReportTemplate(name: 'demo', page: _smallPage, bands: bands);

FilledReport _filled(List<FilledBand> bands) =>
    FilledReport(page: _smallPage, bands: bands);

void main() {
  test('a single page holds all bands that fit', () {
    final LayoutResult r = ReportLayouter()
        .layout(_tpl(), _filled(<FilledBand>[_body(30), _body(30)]));
    expect(r.pages.length, 1);
  });

  test('bands overflow to a second page; the body restarts at bodyTop', () {
    final LayoutResult r = ReportLayouter()
        .layout(_tpl(), _filled(<FilledBand>[_body(30), _body(30), _body(30)]));
    expect(r.pages.length, 2);
    final RectPrimitive rect =
        r.pages[1].primitives.whereType<RectPrimitive>().first;
    expect(rect.bounds, const JetRect(x: 10, y: 10, width: 180, height: 30));
  });

  test('a body band taller than the body capacity overflows with a warning', () {
    // No chrome -> capacity 80; a 100pt band cannot fit even an empty page, so
    // it is placed at bodyTop and overflows (atomic band; no flow solver).
    final LayoutResult r =
        ReportLayouter().layout(_tpl(), _filled(<FilledBand>[_body(100)]));
    expect(r.pages.length, 1);
    final List<Diagnostic> warnings = r.diagnostics.entries
        .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
        .toList();
    expect(warnings.single.message, contains('exceeds body capacity'));
  });

  test('element page coords translate the band-local box by (left, cursorY)',
      () {
    final LayoutResult r = ReportLayouter().layout(
        _tpl(), _filled(<FilledBand>[_body(30, id: 'a'), _body(30, id: 'b')]));
    final List<RectPrimitive> rects =
        r.pages.single.primitives.whereType<RectPrimitive>().toList();
    expect(rects[0].bounds, const JetRect(x: 10, y: 10, width: 180, height: 30));
    expect(rects[1].bounds, const JetRect(x: 10, y: 40, width: 180, height: 30));
  });

  test('page header and footer repeat on every page; footer anchored to bottom',
      () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        _rect('hdr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
      ]),
      ReportBand(type: BandType.pageFooter, height: 20, elements: <ReportElement>[
        _rect('ftr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
      ]),
    ]);
    // header 20 + footer 20 -> bodyTop=30, bodyBottom=70, capacity=40.
    // body 30: band1 at 30 (60<=70); band2: 60+30=90>70 -> page 2.
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(30), _body(30)]));
    expect(r.pages.length, 2);
    for (final PageFrame pf in r.pages) {
      final List<RectPrimitive> rects =
          pf.primitives.whereType<RectPrimitive>().toList();
      expect(
          rects.any((RectPrimitive p) =>
              p.elementId == 'hdr' &&
              p.bounds == const JetRect(x: 10, y: 10, width: 180, height: 20)),
          isTrue);
      expect(
          rects.any((RectPrimitive p) =>
              p.elementId == 'ftr' &&
              p.bounds == const JetRect(x: 10, y: 70, width: 180, height: 20)),
          isTrue);
    }
  });

  test('body primitives paint before chrome (emission z-order)', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        _rect('hdr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    final List<String?> ids = r.pages.single.primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    // Body band 'r' is emitted during pagination; chrome 'hdr' in the post-pass.
    expect(ids.indexOf('r'), lessThan(ids.indexOf('hdr')));
  });

  test('multiple page header bands stack in document order', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 15, elements: <ReportElement>[
        _rect('h1', const JetRect(x: 0, y: 0, width: 180, height: 15)),
      ]),
      ReportBand(type: BandType.pageHeader, height: 15, elements: <ReportElement>[
        _rect('h2', const JetRect(x: 0, y: 0, width: 180, height: 15)),
      ]),
    ]);
    // headerHeight 30 -> bodyTop 40; h1 at top=10, h2 stacked below at 25.
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    final List<RectPrimitive> rects =
        r.pages.single.primitives.whereType<RectPrimitive>().toList();
    expect(rects.firstWhere((RectPrimitive p) => p.elementId == 'h1').bounds,
        const JetRect(x: 10, y: 10, width: 180, height: 15));
    expect(rects.firstWhere((RectPrimitive p) => p.elementId == 'h2').bounds,
        const JetRect(x: 10, y: 25, width: 180, height: 15));
  });

  test('non-detail body bands (title/group/summary) lay out in stream order',
      () {
    FilledBand band(BandType type, String id) => FilledBand(
          type: type,
          height: 15,
          elements: <ReportElement>[
            _rect(id, const JetRect(x: 0, y: 0, width: 180, height: 15)),
          ],
          variables: const <String, JetValue>{},
        );
    // The layouter is type-agnostic for body bands: Fill already ordered the
    // stream (title first, summary last), so layout just stacks them in order.
    final FilledReport filled = _filled(<FilledBand>[
      band(BandType.title, 't'),
      band(BandType.groupHeader, 'gh'),
      band(BandType.detail, 'd'),
      band(BandType.groupFooter, 'gf'),
      band(BandType.summary, 's'),
    ]);
    // 5 * 15 = 75 <= capacity 80 -> one page, stacked in stream order.
    final LayoutResult r = ReportLayouter().layout(_tpl(), filled);
    final List<String?> ids = r.pages.single.primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(ids, <String>['t', 'gh', 'd', 'gf', 's']);
  });

  test('a chrome text expression renders its literal + an info diagnostic', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      const ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        TextElement(
            id: 'pn',
            bounds: JetRect(x: 0, y: 0, width: 180, height: 20),
            text: 'Page',
            expression: r'$V{PAGE_NUMBER}'),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    final TextRunPrimitive run = r.pages.single.primitives
        .whereType<TextRunPrimitive>()
        .firstWhere((TextRunPrimitive p) => p.elementId == 'pn');
    expect(run.lines.map((TextLine l) => l.text).join(), 'Page');
    expect(
        r.diagnostics.entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.info && d.elementId == 'pn'),
        isTrue);
  });

  test('a chrome binding is diagnosed once, not once per page', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      const ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        TextElement(
            id: 'pn',
            bounds: JetRect(x: 0, y: 0, width: 180, height: 20),
            text: 'Page',
            expression: r'$V{PAGE_NUMBER}'),
      ]),
    ]);
    // header 20 -> bodyTop=30, bodyBottom=90, capacity=60; bodies 40+40 overflow
    // to a second page (chrome repeats on both). The scan runs once at setup.
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2); // sanity: genuinely multi-page
    final List<Diagnostic> infos = r.diagnostics.entries
        .where((Diagnostic d) =>
            d.severity == DiagnosticSeverity.info && d.elementId == 'pn')
        .toList();
    expect(infos.length, 1); // diagnosed once at setup, NOT once per page
  });

  test('an unresolved chrome image renders a placeholder + an info diagnostic',
      () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      const ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        ImageElement(
            id: 'logo',
            bounds: JetRect(x: 0, y: 0, width: 40, height: 20),
            source: FieldImageSource('logo')),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(
        r.pages.single.primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'logo'),
        isTrue); // placeholder outline rect
    expect(
        r.diagnostics.entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.info && d.elementId == 'logo'),
        isTrue);
  });

  test('chrome taller than the printable height warns once and still paginates',
      () {
    // header 50 + footer 50 = 100 > content 80 -> capacity = -20.
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 50, elements: <ReportElement>[
        _rect('h', const JetRect(x: 0, y: 0, width: 180, height: 50)),
      ]),
      ReportBand(type: BandType.pageFooter, height: 50, elements: <ReportElement>[
        _rect('f', const JetRect(x: 0, y: 0, width: 180, height: 50)),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(30)]));
    final List<Diagnostic> warnings = r.diagnostics.entries
        .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
        .toList();
    expect(warnings.length, 1); // root-cause only; no per-band capacity spam
    expect(warnings.single.message, contains('leaves no room for body'));
    expect(r.pages, isNotEmpty);
  });

  test('overcommitted chrome: each body band lands on its own page', () {
    // Degenerate case (chrome 50+50 > printable 80 -> bodyCapacity -20): the
    // break guard puts each subsequent band on a fresh page. Characterize this
    // so any future change to overcommit handling is deliberate.
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 50, elements: <ReportElement>[
        _rect('h', const JetRect(x: 0, y: 0, width: 180, height: 50)),
      ]),
      ReportBand(type: BandType.pageFooter, height: 50, elements: <ReportElement>[
        _rect('f', const JetRect(x: 0, y: 0, width: 180, height: 50)),
      ]),
    ]);
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(10), _body(10), _body(10)]));
    expect(r.pages.length, 3);
  });

  test('an empty band stream still produces one chrome-only page', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        _rect('hdr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(const <FilledBand>[]));
    expect(r.pages.length, 1);
    expect(
        r.pages.single.primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'hdr'),
        isTrue);
  });

  test('a noData band lays out as the sole body band', () {
    final FilledReport filled = _filled(<FilledBand>[
      FilledBand(
          type: BandType.noData,
          height: 30,
          elements: <ReportElement>[
            _rect('nd', const JetRect(x: 0, y: 0, width: 180, height: 30)),
          ],
          variables: const <String, JetValue>{}),
    ]);
    final LayoutResult r = ReportLayouter().layout(_tpl(), filled);
    expect(r.pages.length, 1);
    expect(
        r.pages.single.primitives.whereType<RectPrimitive>().single.elementId,
        'nd');
  });

  test('column/background bands are ignored with an info each', () {
    final ReportTemplate tpl = _tpl(bands: const <ReportBand>[
      ReportBand(type: BandType.background, height: 10),
      ReportBand(type: BandType.columnHeader, height: 10),
      ReportBand(type: BandType.columnFooter, height: 10),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.info)
            .length,
        3);
  });

  test('filled.page differing from template.page warns and uses template.page',
      () {
    final FilledReport filled = FilledReport(
        page: const PageFormat(
            width: 999, height: 999, margins: JetEdgeInsets.all(10)),
        bands: <FilledBand>[_body(20)]);
    final LayoutResult r = ReportLayouter().layout(_tpl(), filled);
    expect(r.pages.single.page, _smallPage); // template.page wins
    expect(
        r.diagnostics.entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.warning &&
            d.message.contains('using template.page')),
        isTrue);
  });

  test('determinism — two layouts of identical inputs are equal', () {
    ReportTemplate tpl() => _tpl(bands: <ReportBand>[
          ReportBand(
              type: BandType.pageHeader,
              height: 20,
              elements: <ReportElement>[
                _rect('hdr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
              ]),
        ]);
    FilledReport filled() => _filled(<FilledBand>[_body(30), _body(30)]);
    final LayoutResult a = ReportLayouter().layout(tpl(), filled());
    final LayoutResult b = ReportLayouter().layout(tpl(), filled());
    expect(a.pages, b.pages); // PageFrame has value equality
    List<(DiagnosticSeverity, String, String?)> proj(LayoutResult r) => r
        .diagnostics.entries
        .map((Diagnostic d) => (d.severity, d.message, d.elementId))
        .toList();
    expect(proj(a), proj(b)); // diagnostics by normalized projection
  });
}
