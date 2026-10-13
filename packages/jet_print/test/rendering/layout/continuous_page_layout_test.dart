// ReportLayouter on a continuous (roll-paper) page: no page breaks because the
// page is full, each page as tall as its content and never shorter than the
// authored height, the page footer following the content, and explicit breaks
// (startNewPage) still cutting separate tickets of their own lengths.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/column_layout.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';

// A 200pt-wide roll, 100pt minimum height, 10pt margins -> body starts at
// y=10 and a sheet of this size would hold 80pt of body.
const PageFormat _roll = PageFormat(
  width: 200,
  height: 100,
  margins: JetEdgeInsets.all(10),
  continuous: true,
);

ShapeElement _rect(String id, JetRect bounds) =>
    ShapeElement(id: id, bounds: bounds, kind: ShapeKind.rectangle);

FilledBand _band(double height,
        {required String id, BandType type = BandType.detail, String? group}) =>
    FilledBand(
      type: type,
      height: height,
      group: group,
      elements: <ReportElement>[
        _rect(id, JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
      variables: const <String, JetValue>{},
    );

Band _furniture(BandType type, String id, double height) => Band(
      id: type.name,
      type: type,
      height: height,
      elements: <ReportElement>[
        _rect(id, JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
    );

ReportDefinition _def({
  PageFormat page = _roll,
  PageFurniture furniture = const PageFurniture(),
  List<GroupLevel> groups = const <GroupLevel>[],
  List<ScopeNode> children = const <ScopeNode>[],
}) =>
    ReportDefinition(
      name: 'receipt',
      page: page,
      furniture: furniture,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            for (final GroupLevel g in groups)
              g.copyWith(
                  header: () => Band(
                      id: 'gh-${g.name}',
                      type: BandType.groupHeader,
                      height: 0)),
          ],
          children: children,
        ),
      ),
    );

LayoutResult _layout(ReportDefinition def, List<FilledBand> bands) =>
    ReportLayouter()
        .layoutDefinition(def, FilledReport(page: def.page, bands: bands));

JetRect _bounds(PageFrame page, String id) => page.primitives
    .whereType<RectPrimitive>()
    .firstWhere((RectPrimitive p) => p.elementId == id)
    .bounds;

List<String?> _ids(PageFrame page) => page.primitives
    .whereType<RectPrimitive>()
    .map((RectPrimitive p) => p.elementId)
    .toList();

Iterable<String> _warnings(ReportDiagnostics d) => d.entries
    .where((Diagnostic x) => x.severity == DiagnosticSeverity.warning)
    .map((Diagnostic x) => x.message);

void main() {
  test('content taller than the minimum stays on one page that grows to fit',
      () {
    final LayoutResult r = _layout(_def(), <FilledBand>[
      for (int i = 0; i < 5; i++) _band(30, id: 'd$i'),
    ]);
    expect(r.pages, hasLength(1),
        reason: 'a continuous page never breaks because it is full');
    expect(_ids(r.pages.single), <String?>['d0', 'd1', 'd2', 'd3', 'd4']);
    expect(_bounds(r.pages.single, 'd4').y, 130);
    // 10 top margin + 150 body + 10 bottom margin.
    expect(r.pages.single.page.height, 170);
    expect(r.pages.single.page.width, 200);
    expect(r.pages.single.page.margins, _roll.margins);
  });

  test('short content keeps the authored height as the minimum', () {
    final LayoutResult r = _layout(_def(), <FilledBand>[_band(30, id: 'd')]);
    expect(r.pages.single.page.height, 100);
  });

  test('the page footer follows the content, not a fixed bottom', () {
    final LayoutResult r = _layout(
      _def(
        furniture: PageFurniture(
          pageHeader: _furniture(BandType.pageHeader, 'ph', 10),
          pageFooter: _furniture(BandType.pageFooter, 'pf', 15),
        ),
      ),
      <FilledBand>[for (int i = 0; i < 4; i++) _band(30, id: 'd$i')],
    );
    final PageFrame page = r.pages.single;
    expect(_bounds(page, 'ph').y, 10);
    expect(_bounds(page, 'd0').y, 20);
    // Body ends at 20 + 120 = 140; the footer sits right after it.
    expect(_bounds(page, 'pf').y, 140);
    expect(page.page.height, 140 + 15 + 10);
  });

  test('on a short page the footer sits at the bottom of the minimum height',
      () {
    final LayoutResult r = _layout(
      _def(
        furniture: PageFurniture(
          pageFooter: _furniture(BandType.pageFooter, 'pf', 15),
        ),
      ),
      <FilledBand>[_band(30, id: 'd')],
    );
    final PageFrame page = r.pages.single;
    expect(page.page.height, 100);
    expect(_bounds(page, 'pf').y, 100 - 10 - 15);
  });

  test('startNewPage still cuts separate pages, each its own length', () {
    final LayoutResult r = _layout(
      _def(groups: <GroupLevel>[
        const GroupLevel(
            id: 'g', name: 'station', key: r'$F{station}', startNewPage: true),
      ]),
      <FilledBand>[
        _band(10, id: 'kitchen', type: BandType.groupHeader, group: 'g'),
        for (int i = 0; i < 12; i++) _band(10, id: 'k$i'),
        _band(10, id: 'bar', type: BandType.groupHeader, group: 'g'),
        _band(10, id: 'b0'),
      ],
    );
    expect(r.pages, hasLength(2));
    expect(_ids(r.pages[0]).first, 'kitchen');
    expect(_ids(r.pages[1]), <String?>['bar', 'b0']);
    // 13 bands of 10pt between 10pt margins.
    expect(r.pages[0].page.height, 150);
    // Two bands are shorter than the minimum.
    expect(r.pages[1].page.height, 100);
  });

  test('keepTogether never moves a group: nothing is full on a roll', () {
    final LayoutResult r = _layout(
      _def(groups: <GroupLevel>[
        const GroupLevel(id: 'g', name: 'g', key: r'$F{g}', keepTogether: true),
      ]),
      <FilledBand>[
        _band(60, id: 'lead'),
        _band(10, id: 'gh', type: BandType.groupHeader, group: 'g'),
        _band(40, id: 'gd'),
      ],
    );
    expect(r.pages, hasLength(1));
    expect(r.pages.single.page.height, 10 + 110 + 10);
  });

  test('a band taller than a sheet is not diagnosed as overflowing', () {
    final LayoutResult r = _layout(_def(), <FilledBand>[_band(300, id: 'd')]);
    expect(r.pages.single.page.height, 320);
    expect(_warnings(r.diagnostics), isEmpty);
  });

  test('a page past the PDF size limit renders with one warning', () {
    final LayoutResult r = _layout(_def(), <FilledBand>[
      _band(9000, id: 'a'),
      _band(9000, id: 'b'),
    ]);
    expect(r.pages, hasLength(1));
    expect(r.pages.single.page.height, 18020);
    expect(_warnings(r.diagnostics), hasLength(1));
    expect(_warnings(r.diagnostics).single, contains('14400'));
  });

  test('a label grid lays every label on one page', () {
    const ColumnLayout grid = ColumnLayout(
        columnCount: 2, columnWidth: 80, columnSpacing: 20, rowSpacing: 10);
    final ReportDefinition def = _def(children: <ScopeNode>[
      const BandNode(
          Band(id: 'd', type: BandType.detail, height: 30, columnLayout: grid)),
    ]);
    final LayoutResult r = _layout(def, <FilledBand>[
      for (int i = 0; i < 9; i++) _band(30, id: 'l$i'),
    ]);
    expect(r.pages, hasLength(1));
    // Nine labels in two columns -> five rows at a 40pt pitch.
    expect(_bounds(r.pages.single, 'l8').y, 10 + 4 * 40);
    expect(r.pages.single.page.height, 10 + 4 * 40 + 30 + 10);
  });

  test('the watermark is centred on each page at that page\'s height', () {
    final ReportDefinition def = _def(
      furniture: const PageFurniture(
        watermark:
            Watermark(text: 'COPY', textStyle: JetTextStyle(fontSize: 20)),
      ),
      groups: <GroupLevel>[
        const GroupLevel(id: 'g', name: 'g', key: r'$F{g}', startNewPage: true),
      ],
    );
    final LayoutResult r = _layout(def, <FilledBand>[
      _band(10, id: 'h1', type: BandType.groupHeader, group: 'g'),
      _band(300, id: 'long'),
      _band(10, id: 'h2', type: BandType.groupHeader, group: 'g'),
    ]);
    double centre(PageFrame p) {
      final TextRunPrimitive wm = p.primitives.first as TextRunPrimitive;
      return wm.bounds.y + wm.bounds.height / 2;
    }

    expect(r.pages[0].page.height, 330);
    expect(r.pages[1].page.height, 100);
    expect(centre(r.pages[0]), closeTo(165, 1e-6));
    expect(centre(r.pages[1]), closeTo(50, 1e-6));
  });

  test('a sheet page with the same content still breaks (unchanged)', () {
    final LayoutResult r = _layout(
      _def(page: _roll.copyWith(continuous: false)),
      <FilledBand>[for (int i = 0; i < 5; i++) _band(30, id: 'd$i')],
    );
    expect(r.pages, hasLength(3));
    for (final PageFrame p in r.pages) {
      expect(p.page.height, 100);
    }
  });
}
