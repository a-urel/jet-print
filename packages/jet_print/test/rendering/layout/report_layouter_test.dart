// ReportLayouter: pagination, page chrome, coordinates, diagnostics (008a),
// migrated to the reified model + native layoutDefinition API (spec 024).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
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

// A definition with only page furniture (no body bands; the layouter lays out
// filled.bands, never the body tree).
ReportDefinition _tpl({PageFurniture furniture = const PageFurniture()}) =>
    ReportDefinition(
      name: 'demo',
      page: _smallPage,
      furniture: furniture,
      body: const ReportBody(root: DetailScope(id: 'root')),
    );

// A page-header furniture slot carrying one chrome rect.
Band _headerRect(String id, double height) => Band(
      id: 'pageHeader',
      type: BandType.pageHeader,
      height: height,
      elements: <ReportElement>[
        _rect(id, JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
    );

// A page-footer furniture slot carrying one chrome rect.
Band _footerRect(String id, double height) => Band(
      id: 'pageFooter',
      type: BandType.pageFooter,
      height: height,
      elements: <ReportElement>[
        _rect(id, JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
    );

FilledReport _filled(List<FilledBand> bands) =>
    FilledReport(page: _smallPage, bands: bands);

// A page-chrome band carrying one text element with an optional expression.
Band _chromeText(BandType type, String id, String expression,
        {double height = 20}) =>
    Band(id: type.name, type: type, height: height, elements: <ReportElement>[
      TextElement(
        id: id,
        bounds: JetRect(x: 0, y: 0, width: 180, height: height),
        text: '',
        expression: expression,
      ),
    ]);

// Furniture with a single chrome [band] in its matching slot.
PageFurniture _slot(Band band) {
  switch (band.type) {
    case BandType.pageHeader:
      return PageFurniture(pageHeader: band);
    case BandType.pageFooter:
      return PageFurniture(pageFooter: band);
    case BandType.columnHeader:
      return PageFurniture(columnHeader: band);
    case BandType.columnFooter:
      return PageFurniture(columnFooter: band);
    case BandType.background:
      return PageFurniture(background: band);
    default:
      throw ArgumentError('not a furniture slot: ${band.type}');
  }
}

// A body band carrying one TextElement (type-generic, used for title / detail).
FilledBand _textBand(BandType type, String id, double height) => FilledBand(
      type: type,
      height: height,
      elements: <ReportElement>[
        TextElement(
          id: id,
          bounds: JetRect(x: 0, y: 0, width: 180, height: height),
          text: id,
        ),
      ],
      variables: const <String, JetValue>{},
    );

// Page-absolute y of the TextRunPrimitive with [id] on [page].
double _textRunY(PageFrame page, String id) => page.primitives
    .whereType<TextRunPrimitive>()
    .firstWhere((TextRunPrimitive p) => p.elementId == id)
    .bounds
    .y;

// True when no TextRunPrimitive with [id] exists on [page].
bool _textRunAbsent(PageFrame page, String id) => !page.primitives
    .whereType<TextRunPrimitive>()
    .any((TextRunPrimitive p) => p.elementId == id);

// The rendered text of the chrome TextRunPrimitive with [id] on [page].
String _chromeRun(PageFrame page, String id) => page.primitives
    .whereType<TextRunPrimitive>()
    .firstWhere((TextRunPrimitive p) => p.elementId == id)
    .lines
    .map((TextLine l) => l.text)
    .join();

// A group-typed (or plain) body band carrying optional group identity.
FilledBand _gband(BandType type,
        {String? group, double height = 20, String id = 'x'}) =>
    FilledBand(
      type: type,
      height: height,
      group: group,
      elements: <ReportElement>[
        _rect(id, JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
      variables: const <String, JetValue>{},
    );

// One authored group-header band per group, so the definition is consistent
// with the directly-built filled stream (a real Fill produces both). The
// header-less advisory then fires only for groups that genuinely lack an
// authored header. These header bands are inert at layout time — the layouter
// lays out filled.bands, not the definition's group-header bands.
ReportDefinition _tplWithGroups(List<GroupLevel> groups) => ReportDefinition(
      name: 'demo',
      page: _smallPage,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            for (final GroupLevel g in groups)
              g.header == null
                  ? g.copyWith(
                      header: Band(
                          id: 'gh-${g.name}',
                          type: BandType.groupHeader,
                          height: 0))
                  : g,
          ],
        ),
      ),
    );

void main() {
  test('a single page holds all bands that fit', () {
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(_tpl(), _filled(<FilledBand>[_body(30), _body(30)]));
    expect(r.pages.length, 1);
  });

  test('bands overflow to a second page; the body restarts at bodyTop', () {
    final LayoutResult r = ReportLayouter().layoutDefinition(
        _tpl(), _filled(<FilledBand>[_body(30), _body(30), _body(30)]));
    expect(r.pages.length, 2);
    final RectPrimitive rect =
        r.pages[1].primitives.whereType<RectPrimitive>().first;
    expect(rect.bounds, const JetRect(x: 10, y: 10, width: 180, height: 30));
  });

  test('a body band taller than the body capacity overflows with a warning',
      () {
    // No chrome -> capacity 80; a 100pt band cannot fit even an empty page, so
    // it is placed at bodyTop and overflows (atomic band; no flow solver).
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(_tpl(), _filled(<FilledBand>[_body(100)]));
    expect(r.pages.length, 1);
    final List<Diagnostic> warnings = r.diagnostics.entries
        .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
        .toList();
    expect(warnings.single.message, contains('exceeds body capacity'));
  });

  test('element page coords translate the band-local box by (left, cursorY)',
      () {
    final LayoutResult r = ReportLayouter().layoutDefinition(
        _tpl(), _filled(<FilledBand>[_body(30, id: 'a'), _body(30, id: 'b')]));
    final List<RectPrimitive> rects =
        r.pages.single.primitives.whereType<RectPrimitive>().toList();
    expect(
        rects[0].bounds, const JetRect(x: 10, y: 10, width: 180, height: 30));
    expect(
        rects[1].bounds, const JetRect(x: 10, y: 40, width: 180, height: 30));
  });

  test('page header and footer repeat on every page; footer anchored to bottom',
      () {
    final ReportDefinition tpl = _tpl(
        furniture: PageFurniture(
      pageHeader: _headerRect('hdr', 20),
      pageFooter: _footerRect('ftr', 20),
    ));
    // header 20 + footer 20 -> bodyTop=30, bodyBottom=70, capacity=40.
    // body 30: band1 at 30 (60<=70); band2: 60+30=90>70 -> page 2.
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(30), _body(30)]));
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
    final ReportDefinition tpl =
        _tpl(furniture: PageFurniture(pageHeader: _headerRect('hdr', 20)));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
    final List<String?> ids = r.pages.single.primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    // Body band 'r' is emitted during pagination; chrome 'hdr' in the post-pass.
    expect(ids.indexOf('r'), lessThan(ids.indexOf('hdr')));
  });

  test('multiple page header bands stack in document order', () {
    // The reified PageFurniture.pageHeader is a single band; two stacked 15pt
    // header bands are faithfully one 30pt header band whose two elements sit at
    // band-local y=0 and y=15 — byte-identical placement (h1@10, h2@25).
    final ReportDefinition tpl = _tpl(
        furniture: PageFurniture(
      pageHeader: const Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 30,
          elements: <ReportElement>[
            ShapeElement(
                id: 'h1',
                bounds: JetRect(x: 0, y: 0, width: 180, height: 15),
                kind: ShapeKind.rectangle),
            ShapeElement(
                id: 'h2',
                bounds: JetRect(x: 0, y: 15, width: 180, height: 15),
                kind: ShapeKind.rectangle),
          ]),
    ));
    // headerHeight 30 -> bodyTop 40; h1 at top=10, h2 stacked below at 25.
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
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
    final LayoutResult r = ReportLayouter().layoutDefinition(_tpl(), filled);
    final List<String?> ids = r.pages.single.primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(ids, <String>['t', 'gh', 'd', 'gf', 's']);
  });

  test('a chrome text expression is evaluated (no "not evaluated" info)', () {
    final ReportDefinition tpl = _tpl(
        furniture:
            _slot(_chromeText(BandType.pageHeader, 'pn', r'$V{PAGE_NUMBER}')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages.single, 'pn'), '1'); // evaluated, not the literal
    expect(r.diagnostics.entries.where((Diagnostic d) => d.elementId == 'pn'),
        isEmpty); // PAGE_NUMBER resolves cleanly -> no diagnostic
  });

  test('a chrome binding is diagnosed once, not once per page', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(_chromeText(BandType.pageHeader, 'pn', r'$F{x}')));
    // header 20 -> bodyTop=30 bodyBottom=90 capacity=60; bodies 40+40 -> 2 pages.
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2);
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) =>
                d.severity == DiagnosticSeverity.warning && d.elementId == 'pn')
            .length,
        1); // once at the pre-pass, NOT once per page
  });

  test('an unresolved chrome image renders a placeholder + an info diagnostic',
      () {
    final ReportDefinition tpl = _tpl(
        furniture: const PageFurniture(
            pageHeader: Band(
                id: 'pageHeader',
                type: BandType.pageHeader,
                height: 20,
                elements: <ReportElement>[
          ImageElement(
              id: 'logo',
              bounds: JetRect(x: 0, y: 0, width: 40, height: 20),
              source: FieldImageSource('logo')),
        ])));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
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
    final ReportDefinition tpl = _tpl(
        furniture: PageFurniture(
      pageHeader: _headerRect('h', 50),
      pageFooter: _footerRect('f', 50),
    ));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(30)]));
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
    final ReportDefinition tpl = _tpl(
        furniture: PageFurniture(
      pageHeader: _headerRect('h', 50),
      pageFooter: _footerRect('f', 50),
    ));
    final LayoutResult r = ReportLayouter().layoutDefinition(
        tpl, _filled(<FilledBand>[_body(10), _body(10), _body(10)]));
    expect(r.pages.length, 3);
  });

  test('an empty band stream still produces one chrome-only page', () {
    final ReportDefinition tpl =
        _tpl(furniture: PageFurniture(pageHeader: _headerRect('hdr', 20)));
    final LayoutResult r =
        ReportLayouter().layoutDefinition(tpl, _filled(const <FilledBand>[]));
    expect(r.pages.length, 1);
    expect(
        r.pages.single.primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'hdr'),
        isTrue);
  });

  test('a noData band lays out as the sole body band', () {
    final FilledReport filled = _filled(<FilledBand>[
      FilledBand(type: BandType.noData, height: 30, elements: <ReportElement>[
        _rect('nd', const JetRect(x: 0, y: 0, width: 180, height: 30)),
      ], variables: const <String, JetValue>{}),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(_tpl(), filled);
    expect(r.pages.length, 1);
    expect(
        r.pages.single.primitives.whereType<RectPrimitive>().single.elementId,
        'nd');
  });

  test('column/background bands are ignored with an info each', () {
    final ReportDefinition tpl = _tpl(
        furniture: const PageFurniture(
      background: Band(id: 'bg', type: BandType.background, height: 10),
      columnHeader: Band(id: 'ch', type: BandType.columnHeader, height: 10),
      columnFooter: Band(id: 'cf', type: BandType.columnFooter, height: 10),
    ));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
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
    final LayoutResult r = ReportLayouter().layoutDefinition(_tpl(), filled);
    expect(r.pages.single.page, _smallPage); // template.page wins
    expect(
        r.diagnostics.entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.warning &&
            d.message.contains('using template.page')),
        isTrue);
  });

  test('determinism — two layouts of identical inputs are equal', () {
    ReportDefinition tpl() =>
        _tpl(furniture: PageFurniture(pageHeader: _headerRect('hdr', 20)));
    FilledReport filled() => _filled(<FilledBand>[_body(30), _body(30)]);
    final LayoutResult a = ReportLayouter().layoutDefinition(tpl(), filled());
    final LayoutResult b = ReportLayouter().layoutDefinition(tpl(), filled());
    expect(a.pages, b.pages); // PageFrame has value equality
    List<(DiagnosticSeverity, String, String?)> proj(LayoutResult r) =>
        r.diagnostics.entries
            .map((Diagnostic d) => (d.severity, d.message, d.elementId))
            .toList();
    expect(proj(a), proj(b)); // diagnostics by normalized projection
  });

  test('a group header reprints at the top of a continuation page when flagged',
      () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(
          id: 'g', name: 'g', key: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
      _gband(BandType.detail, height: 30, id: 'd3'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    final List<RectPrimitive> p2 =
        r.pages[1].primitives.whereType<RectPrimitive>().toList();
    expect(p2.first.elementId, 'GH'); // reprinted header is first on page 2
    expect(
        p2.first.bounds, const JetRect(x: 10, y: 10, width: 180, height: 20));
  });

  test('a group header does not reprint when the flag is off (default)', () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(id: 'g', name: 'g', key: r'$F{g}'),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
      _gband(BandType.detail, height: 30, id: 'd3'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'GH'),
        isFalse);
  });

  test('nested group headers reprint outer-then-inner on a continuation page',
      () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(
          id: 'region',
          name: 'region',
          key: r'$F{region}',
          reprintHeaderOnEachPage: true),
      const GroupLevel(
          id: 'city',
          name: 'city',
          key: r'$F{city}',
          reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'region', height: 20, id: 'RH'),
      _gband(BandType.groupHeader, group: 'city', height: 20, id: 'CH'),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    final List<String?> ids = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(ids.take(2).toList(), <String>['RH', 'CH']); // outer then inner
  });

  test('a group with multiple header bands reprints all of them in order', () {
    // A group owns a single header band in the reified model; the legacy "two
    // 15pt group-header bands" is faithfully one 30pt group-header band carrying
    // two elements (H1@y0, H2@y15) — same reprint geometry and order.
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(
          id: 'g', name: 'g', key: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      FilledBand(
          type: BandType.groupHeader,
          height: 30,
          group: 'g',
          elements: const <ReportElement>[
            ShapeElement(
                id: 'H1',
                bounds: JetRect(x: 0, y: 0, width: 180, height: 15),
                kind: ShapeKind.rectangle),
            ShapeElement(
                id: 'H2',
                bounds: JetRect(x: 0, y: 15, width: 180, height: 15),
                kind: ShapeKind.rectangle),
          ],
          variables: const <String, JetValue>{}),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    final List<String?> ids = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(ids.take(2).toList(), <String>['H1', 'H2']);
  });

  test(
      'a break between an inner footer and an outer footer reprints only the '
      'outer header', () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(
          id: 'region',
          name: 'region',
          key: r'$F{region}',
          reprintHeaderOnEachPage: true),
      const GroupLevel(
          id: 'city',
          name: 'city',
          key: r'$F{city}',
          reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'region', height: 10, id: 'RH'),
      _gband(BandType.groupHeader, group: 'city', height: 10, id: 'CH'),
      _gband(BandType.detail, height: 40, id: 'd1'),
      _gband(BandType.groupFooter, group: 'city', height: 15, id: 'CF'),
      _gband(BandType.groupFooter, group: 'region', height: 15, id: 'RF'),
    ]);
    // RH@10 CH@20 d1@30..70 CF@70..85; RF (85+15>90) -> page 2. City closed at
    // its footer-run end, so only region reprints.
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    final Set<String?> p2 = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toSet();
    expect(p2.contains('RH'), isTrue);
    expect(p2.contains('CH'), isFalse);
  });

  test('a break between the final group footer and summary reprints no header',
      () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(
          id: 'g', name: 'g', key: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH'),
      _gband(BandType.detail, height: 50, id: 'd1'),
      _gband(BandType.groupFooter, group: 'g', height: 15, id: 'GF'),
      _gband(BandType.summary, height: 20, id: 'S'),
    ]);
    // GH@10 d1@20..70 GF@70..85; S (85+20>90) -> page 2. Group closed before S.
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    final Set<String?> p2 = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toSet();
    expect(p2.contains('S'), isTrue);
    expect(p2.contains('GH'), isFalse);
  });

  test('a group-typed band with null group lays out as a plain band', () {
    final ReportDefinition tpl = _tplWithGroups(const <GroupLevel>[]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, height: 30, id: 'GH'), // group: null
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2); // GH@10 d1@40 d2(70+30>90)->page2
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'GH'),
        isFalse); // not reprinted
    expect(r.diagnostics.entries, isEmpty); // no diagnostic
  });

  test('a group band naming an undeclared group lays out as a plain band', () {
    final ReportDefinition tpl = _tplWithGroups(const <GroupLevel>[]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'ghost', height: 30, id: 'GH'),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2); // 'ghost' undeclared -> plain band
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'GH'),
        isFalse); // not reprinted
    expect(r.diagnostics.entries, isEmpty); // no declared groups -> no advisory
  });

  test('a flag on a header-less group emits an info and changes nothing', () {
    // A flagged group with NO authored group-header band.
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: _smallPage,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
                id: 'g',
                name: 'g',
                key: r'$F{g}',
                reprintHeaderOnEachPage: true),
          ],
        ),
      ),
    );
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.detail, height: 30, id: 'd1'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.info)
            .length,
        1);
  });

  test('a flagged group with an authored header gets no advisory on empty data',
      () {
    // The Medium regression: empty data emits only noData (no group bands), but
    // the definition DOES author a header, so no advisory must fire.
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: _smallPage,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
                id: 'g',
                name: 'g',
                key: r'$F{g}',
                reprintHeaderOnEachPage: true,
                header:
                    Band(id: 'gh-g', type: BandType.groupHeader, height: 0)),
          ],
        ),
      ),
    );
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.noData, height: 20, id: 'ND'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.info),
        isEmpty);
  });

  test('a header-only group is closed by summary (no reprint above summary)',
      () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(
          id: 'g', name: 'g', key: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH'),
      _gband(BandType.detail, height: 60, id: 'd1'),
      _gband(BandType.summary, height: 25, id: 'S'),
    ]);
    // GH@10..20 d1@20..80; S (80+25>90) -> page 2. The header-only group (no
    // footer) is closed by the summary rule, so no header reprints above S.
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    final Set<String?> p2 = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toSet();
    expect(p2.contains('S'), isTrue);
    expect(p2.contains('GH'), isFalse);
  });

  test('group-aware layout is deterministic', () {
    ReportDefinition tpl() => _tplWithGroups(<GroupLevel>[
          const GroupLevel(
              id: 'g', name: 'g', key: r'$F{g}', reprintHeaderOnEachPage: true),
        ]);
    FilledReport filled() => _filled(<FilledBand>[
          _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
          _gband(BandType.detail, height: 30, id: 'd1'),
          _gband(BandType.detail, height: 30, id: 'd2'),
          _gband(BandType.detail, height: 30, id: 'd3'),
        ]);
    final LayoutResult a = ReportLayouter().layoutDefinition(tpl(), filled());
    final LayoutResult b = ReportLayouter().layoutDefinition(tpl(), filled());
    expect(a.pages, b.pages); // PageFrame has value equality
    List<(DiagnosticSeverity, String, String?)> proj(LayoutResult r) =>
        r.diagnostics.entries
            .map((Diagnostic d) => (d.severity, d.message, d.elementId))
            .toList();
    expect(proj(a), proj(b)); // diagnostics by normalized projection
  });

  test(
      'keepTogether moves a whole group to a fresh page when it does not fit '
      'the remainder', () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(id: 'g', name: 'g', key: r'$F{g}', keepTogether: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.detail, height: 60, id: 'pre'),
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 30, id: 'gd1'),
    ]);
    // pre@10..70; group extent 50 doesn't fit remainder (70..90) but fits a
    // fresh page -> moved whole to page 2.
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[0].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet(),
        <String>{'pre'});
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet()
            .containsAll(<String>{'GH', 'gd1'}),
        isTrue);
    // one break per band: GH lands at bodyTop on page 2 (no blank page).
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .firstWhere((RectPrimitive p) => p.elementId == 'GH')
            .bounds
            .y,
        10);
  });

  test('keepTogether does not force-break a group taller than the page', () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(id: 'g', name: 'g', key: r'$F{g}', keepTogether: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.detail, height: 40, id: 'pre'),
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 70, id: 'big'),
    ]);
    // group extent 90 > bodyCapacity 80 -> not force-broken; it splits.
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[0].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet(),
        <String>{'pre', 'GH'});
    expect(r.pages[1].primitives.whereType<RectPrimitive>().single.elementId,
        'big');
  });

  List<String?> rectIdsOn(LayoutResult r, int page) => r.pages[page].primitives
      .whereType<RectPrimitive>()
      .map((RectPrimitive p) => p.elementId)
      .toList();

  test('startNewPage starts every group instance after the first on a new page',
      () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(id: 'g', name: 'g', key: r'$F{g}', startNewPage: true),
    ]);
    // Three instances of group g; together they fit one page (60 <= capacity
    // 80), so only startNewPage can force the split into three pages.
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH1'),
      _gband(BandType.detail, height: 10, id: 'd1'),
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH2'),
      _gband(BandType.detail, height: 10, id: 'd2'),
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH3'),
      _gband(BandType.detail, height: 10, id: 'd3'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 3);
    expect(rectIdsOn(r, 0), <String>['GH1', 'd1']);
    expect(rectIdsOn(r, 1), <String>['GH2', 'd2']);
    expect(rectIdsOn(r, 2), <String>['GH3', 'd3']);
    // The first instance does not push a leading blank page: GH1 sits at
    // bodyTop on page 1.
    expect(
        r.pages[0].primitives
            .whereType<RectPrimitive>()
            .firstWhere((RectPrimitive p) => p.elementId == 'GH1')
            .bounds
            .y,
        10);
  });

  test('startNewPage off (default) keeps fitting group instances on one page',
      () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(id: 'g', name: 'g', key: r'$F{g}'),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH1'),
      _gband(BandType.detail, height: 10, id: 'd1'),
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH2'),
      _gband(BandType.detail, height: 10, id: 'd2'),
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH3'),
      _gband(BandType.detail, height: 10, id: 'd3'),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 1);
  });

  test('keepTogether accounts for repeated outer headers (splits, not moved)',
      () {
    final ReportDefinition tpl = _tplWithGroups(<GroupLevel>[
      const GroupLevel(
          id: 'region',
          name: 'region',
          key: r'$F{region}',
          reprintHeaderOnEachPage: true),
      const GroupLevel(
          id: 'city', name: 'city', key: r'$F{city}', keepTogether: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'region', height: 20, id: 'RH'),
      _gband(BandType.detail, height: 30, id: 'fill'),
      _gband(BandType.groupHeader, group: 'city', height: 20, id: 'CH'),
      _gband(BandType.detail, height: 50, id: 'cd1'),
    ]);
    // city extent 70 fits a raw page (80) but NOT after region's repeated header
    // (80-20=60), so it is NOT moved whole -> it splits: CH on page 1, cd1 on
    // page 2 below the reprinted RH.
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[0].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet(),
        containsAll(<String>{'RH', 'fill', 'CH'}));
    final List<String?> p2 = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(p2, <String>['RH', 'cd1']); // region header reprinted, then cd1
  });

  test(
      'a reprinted header lands at bodyTop below page chrome (not content-top)',
      () {
    // 20pt pageHeader pushes bodyTop to 10+20=30 (bodyBottom 90, capacity 60).
    // A reprint that used content-top would land the header at y=10; this locks
    // reEmitHeaders to bodyTop.
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: _smallPage,
      furniture: const PageFurniture(
          pageHeader:
              Band(id: 'pageHeader', type: BandType.pageHeader, height: 20)),
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
                id: 'g',
                name: 'g',
                key: r'$F{g}',
                reprintHeaderOnEachPage: true,
                header:
                    Band(id: 'gh-g', type: BandType.groupHeader, height: 0)),
          ],
        ),
      ),
    );
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 25, id: 'd1'),
      _gband(BandType.detail, height: 25, id: 'd2'),
    ]);
    // GH@30..50 d1@50..75; d2 (75+25>90) -> page 2, GH reprinted at bodyTop=30.
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    final List<RectPrimitive> p2 =
        r.pages[1].primitives.whereType<RectPrimitive>().toList();
    expect(p2.first.elementId, 'GH');
    expect(
        p2.first.bounds, const JetRect(x: 10, y: 30, width: 180, height: 20));
  });

  test('keepTogether respects page chrome in the fit decision and fresh top',
      () {
    // With a 20pt pageHeader, bodyTop=30/bodyBottom=90/capacity=60. The group
    // (extent 50) would FIT the remainder with no chrome (pre@10..35, 35+50=85<=90,
    // one page); the chrome shrinks the remainder so it is moved whole to page 2,
    // landing at bodyTop=30.
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: _smallPage,
      furniture: const PageFurniture(
          pageHeader:
              Band(id: 'pageHeader', type: BandType.pageHeader, height: 20)),
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
                id: 'g',
                name: 'g',
                key: r'$F{g}',
                keepTogether: true,
                header:
                    Band(id: 'gh-g', type: BandType.groupHeader, height: 0)),
          ],
        ),
      ),
    );
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.detail, height: 25, id: 'pre'),
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 30, id: 'gd1'),
    ]);
    // pre@30..55; group extent 50: 55+50=105>90 -> moved whole to page 2.
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[0].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet(),
        <String>{'pre'});
    final List<RectPrimitive> p2 =
        r.pages[1].primitives.whereType<RectPrimitive>().toList();
    expect(p2.map((RectPrimitive p) => p.elementId).toSet(),
        <String>{'GH', 'gd1'});
    expect(
        p2.firstWhere((RectPrimitive p) => p.elementId == 'GH').bounds.y, 30);
  });

  test('Page N of M substitutes the page number and count per page', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(_chromeText(BandType.pageFooter, 'pn',
            r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}')));
    // footer 20 -> bodyTop=10 bodyBottom=70 capacity=60; one body(40) per page.
    final LayoutResult r = ReportLayouter().layoutDefinition(
        tpl, _filled(<FilledBand>[_body(40), _body(40), _body(40)]));
    expect(r.pages.length, 3);
    expect(_chromeRun(r.pages[0], 'pn'), 'Page 1 of 3');
    expect(_chromeRun(r.pages[1], 'pn'), 'Page 2 of 3');
    expect(_chromeRun(r.pages[2], 'pn'), 'Page 3 of 3');
  });

  test('a bare PAGE_NUMBER renders an integer, not 1.0', () {
    final ReportDefinition tpl = _tpl(
        furniture:
            _slot(_chromeText(BandType.pageFooter, 'pn', r'$V{PAGE_NUMBER}')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2);
    expect(_chromeRun(r.pages[0], 'pn'), '1');
    expect(_chromeRun(r.pages[1], 'pn'), '2');
  });

  test('first/last-page conditions work via string equality', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(_chromeText(BandType.pageFooter, 'pn',
            r'$V{PAGE_NUMBER} == "1" ? "FIRST" : ($V{PAGE_NUMBER} == $V{PAGE_COUNT} ? "LAST" : "MID")')));
    final LayoutResult r = ReportLayouter().layoutDefinition(
        tpl, _filled(<FilledBand>[_body(40), _body(40), _body(40)]));
    expect(_chromeRun(r.pages[0], 'pn'), 'FIRST');
    expect(_chromeRun(r.pages[1], 'pn'), 'MID');
    expect(_chromeRun(r.pages[2], 'pn'), 'LAST');
  });

  test('a chrome param resolves from FilledReport.params', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(_chromeText(BandType.pageFooter, 'pn', r'$P{title}')));
    final FilledReport filled = FilledReport(
        page: _smallPage,
        bands: <FilledBand>[_body(20)],
        params: <String, JetValue>{'title': const JetString('Q1 Report')});
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 1);
    expect(_chromeRun(r.pages[0], 'pn'), 'Q1 Report');
  });

  test('substitution is fixed-bounds: long text does not add a page', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(_chromeText(BandType.pageFooter, 'pn',
            r'"this is a very long footer that wraps well beyond the box " + $V{PAGE_NUMBER}')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
    expect(r.pages.length, 1); // wrapped text never repaginates the chrome
  });

  test('a chrome parse error renders !ERR and one error diagnostic', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(
            _chromeText(BandType.pageFooter, 'pn', r'$V{PAGE_NUMBER} +')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2);
    expect(_chromeRun(r.pages[0], 'pn'), '!ERR');
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) =>
                d.severity == DiagnosticSeverity.error && d.elementId == 'pn')
            .length,
        1); // once, not once per page
  });

  test('an unavailable field hidden in an untaken branch still warns once', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(_chromeText(BandType.pageFooter, 'pn',
            r'$V{PAGE_NUMBER} == "9" ? $F{x} : "ok"')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(_chromeRun(r.pages[0], 'pn'), 'ok'); // condition false on every page
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) =>
                d.severity == DiagnosticSeverity.warning && d.elementId == 'pn')
            .length,
        1); // static analysis sees $F{x} despite the branch never being taken
  });

  test('a bare unavailable field renders blank; in an operation renders !ERR',
      () {
    final ReportDefinition bare = _tpl(
        furniture: _slot(_chromeText(BandType.pageFooter, 'pn', r'$F{x}')));
    final LayoutResult rb = ReportLayouter()
        .layoutDefinition(bare, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(rb.pages[0], 'pn'), ''); // JetNull -> blank
    expect(
        rb.diagnostics.entries
            .where((Diagnostic d) => d.elementId == 'pn')
            .length,
        1); // one structural warning, no extra runtime error

    final ReportDefinition inOp = _tpl(
        furniture:
            _slot(_chromeText(BandType.pageFooter, 'pn', r'"a" + $F{x}')));
    final LayoutResult ro = ReportLayouter()
        .layoutDefinition(inOp, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(ro.pages[0], 'pn'),
        '!ERR'); // JetNull poisons "+" -> JetError
    expect(
        ro.diagnostics.entries
            .where((Diagnostic d) => d.elementId == 'pn')
            .length,
        1); // structural warning only; runtime error suppressed (already flagged)
  });

  test('an absent param renders blank with no diagnostic', () {
    final ReportDefinition tpl = _tpl(
        furniture:
            _slot(_chromeText(BandType.pageFooter, 'pn', r'$P{missing}')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages[0], 'pn'), '');
    expect(r.diagnostics.entries.where((Diagnostic d) => d.elementId == 'pn'),
        isEmpty);
  });

  test('a chrome function (CONCAT) evaluates through the registry', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(_chromeText(
            BandType.pageFooter, 'pn', r'CONCAT("Page ", $V{PAGE_NUMBER})')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages[0], 'pn'),
        'Page 1'); // built-in via default registry
  });

  test('an injected function registry is used for chrome evaluation', () {
    // STARS is not a built-in: it can only resolve via the injected registry,
    // proving constructor injection + PageEvalContext.functions are wired.
    final JetFunctionRegistry functions = JetFunctionRegistry()
      ..register('STARS',
          (List<JetValue> args, EvalContext ctx) => const JetString('***'));
    final ReportDefinition tpl = _tpl(
        furniture: _slot(
            _chromeText(BandType.pageFooter, 'pn', r'STARS($V{PAGE_NUMBER})')));
    final LayoutResult r = ReportLayouter(functions: functions)
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages[0], 'pn'), '***');
  });

  test('a bare non-page variable warns once and renders blank', () {
    final ReportDefinition tpl = _tpl(
        furniture: _slot(_chromeText(BandType.pageFooter, 'pn', r'$V{total}')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2);
    expect(
        _chromeRun(r.pages[0], 'pn'), ''); // non-page var -> JetNull -> blank
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) =>
                d.severity == DiagnosticSeverity.warning && d.elementId == 'pn')
            .length,
        1); // once at the pre-pass, NOT once per page
  });

  test('a non-page variable consumed by an operator renders !ERR', () {
    final ReportDefinition tpl = _tpl(
        furniture:
            _slot(_chromeText(BandType.pageFooter, 'pn', r'"x" + $V{total}')));
    final LayoutResult r = ReportLayouter()
        .layoutDefinition(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages[0], 'pn'),
        '!ERR'); // JetNull poisons "+" -> JetError
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) => d.elementId == 'pn')
            .length,
        1); // structural warning only; runtime error suppressed (already flagged)
  });

  test('page-scoped substitution is deterministic', () {
    ReportDefinition tpl() => _tpl(
        furniture: _slot(_chromeText(BandType.pageFooter, 'pn',
            r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}')));
    FilledReport filled() => _filled(<FilledBand>[_body(40), _body(40)]);
    final LayoutResult a = ReportLayouter().layoutDefinition(tpl(), filled());
    final LayoutResult b = ReportLayouter().layoutDefinition(tpl(), filled());
    expect(a.pages, b.pages);
    List<(DiagnosticSeverity, String, String?)> proj(LayoutResult r) =>
        r.diagnostics.entries
            .map((Diagnostic d) => (d.severity, d.message, d.elementId))
            .toList();
    expect(proj(a), proj(b));
  });

  // ── Title-before-pageHeader (fix) ─────────────────────────────────────────
  //
  // _smallPage: 200×100, margins=10 → printable top=10, content height=80.
  // ph=30 (pageHeader), th=20 (title).
  // After fix: page 0 → title at [10,30], pageHeader at [30,60].
  // Before fix: page 0 → pageHeader at [10,40], title at [40,60].

  test(
      'title band prints above the page header on page 1 '
      '(single-page report)', () {
    // pageHeader ph=30, title th=20.
    // bodyTop = top+ph = 40; capacity = 80-30 = 50.
    // title (th=20) consumes 20 of capacity → remaining 30.
    // One detail band of 30 fills the rest exactly → 1 page.
    const double ph = 30;
    const double th = 20;
    final ReportDefinition tpl = ReportDefinition(
      name: 'titleOrderTest',
      page: _smallPage,
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: ph,
          elements: <ReportElement>[
            TextElement(
              id: 'colHead',
              bounds: JetRect(x: 0, y: 0, width: 180, height: ph),
              text: 'colHead',
            ),
          ],
        ),
      ),
      body: ReportBody(
        title: Band(
          id: 'title',
          type: BandType.title,
          height: th,
          elements: <ReportElement>[
            TextElement(
              id: 'rptHdr',
              bounds: JetRect(x: 0, y: 0, width: 180, height: th),
              text: 'rptHdr',
            ),
          ],
        ),
        root: const DetailScope(id: 'root'),
      ),
    );
    final FilledReport filled = _filled(<FilledBand>[
      _textBand(BandType.title, 'rptHdr', th),
      _textBand(BandType.detail, 'row0', 30),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 1);
    final PageFrame p0 = r.pages[0];
    // title at margins.top (10); pageHeader below title (10+th=30).
    expect(_textRunY(p0, 'rptHdr'), _smallPage.margins.top);
    expect(_textRunY(p0, 'colHead'), _smallPage.margins.top + th);
    expect(_textRunY(p0, 'rptHdr'), lessThan(_textRunY(p0, 'colHead')));
  });

  test(
      'title absent on page 2; page header at margins.top on every page '
      '(two-page report)', () {
    // pageHeader ph=30, title th=20.
    // bodyTop = top+ph = 40; capacity = 80-30 = 50.
    // Page 0 plan: title(20) + detail(30) = 50 (full). Page 1: detail(30).
    const double ph = 30;
    const double th = 20;
    final ReportDefinition tpl = ReportDefinition(
      name: 'titleOrderTwoPage',
      page: _smallPage,
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: ph,
          elements: <ReportElement>[
            TextElement(
              id: 'colHead',
              bounds: JetRect(x: 0, y: 0, width: 180, height: ph),
              text: 'colHead',
            ),
          ],
        ),
      ),
      body: ReportBody(
        title: Band(
          id: 'title',
          type: BandType.title,
          height: th,
          elements: <ReportElement>[
            TextElement(
              id: 'rptHdr',
              bounds: JetRect(x: 0, y: 0, width: 180, height: th),
              text: 'rptHdr',
            ),
          ],
        ),
        root: const DetailScope(id: 'root'),
      ),
    );
    final FilledReport filled = _filled(<FilledBand>[
      _textBand(BandType.title, 'rptHdr', th),
      _textBand(BandType.detail, 'row0', 30),
      _textBand(BandType.detail, 'row1', 30),
    ]);
    final LayoutResult r = ReportLayouter().layoutDefinition(tpl, filled);
    expect(r.pages.length, 2);

    // Page 0: rptHdr at top (10), colHead below at 10+th=30.
    final PageFrame p0 = r.pages[0];
    expect(_textRunY(p0, 'rptHdr'), _smallPage.margins.top);
    expect(_textRunY(p0, 'colHead'), _smallPage.margins.top + th);
    expect(_textRunY(p0, 'rptHdr'), lessThan(_textRunY(p0, 'colHead')));

    // Page 1: pageHeader at margins.top; no title.
    final PageFrame p1 = r.pages[1];
    expect(_textRunY(p1, 'colHead'), _smallPage.margins.top);
    expect(_textRunAbsent(p1, 'rptHdr'), isTrue,
        reason: 'title should not appear on page 2');
  });
}
