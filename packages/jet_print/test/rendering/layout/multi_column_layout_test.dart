// Multi-column label grid placement (spec 034).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/column_layout.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';

// 200x100 page, 10pt margins -> body left=10 top=10, capacity 80 (no furniture).
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

// 2 columns of 80pt, 20pt gutter, 10pt row gap; 30pt labels.
// rowsPerPage = floor((80+10)/(30+10)) = 2 -> cellsPerPage = 4.
const ColumnLayout _grid = ColumnLayout(
    columnCount: 2, columnWidth: 80, columnSpacing: 20, rowSpacing: 10);

ReportDefinition _def(ColumnLayout? grid) => ReportDefinition(
      name: 'labels',
      page: _page,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'd', type: BandType.detail, height: 30, columnLayout: grid)),
        ]),
      ),
    );

// N detail bands, each a single 80x30 rect filling its cell, ids r0..r(N-1).
FilledReport _filled(int n) => FilledReport(
      page: _page,
      bands: <FilledBand>[
        for (int i = 0; i < n; i++)
          FilledBand(
            type: BandType.detail,
            height: 30,
            elements: <ReportElement>[
              ShapeElement(
                  id: 'r$i',
                  bounds: const JetRect(x: 0, y: 0, width: 80, height: 30),
                  kind: ShapeKind.rectangle),
            ],
            variables: const <String, JetValue>{},
          ),
      ],
    );

JetRect _boundsOf(LayoutResult r, int page, String id) =>
    r.pages[page].primitives
        .whereType<RectPrimitive>()
        .firstWhere((RectPrimitive p) => p.elementId == id)
        .bounds;

void main() {
  test('6 labels fill a 2x2 grid across two pages in horizontal order', () {
    final LayoutResult r =
        ReportLayouter().layoutDefinition(_def(_grid), _filled(6));
    expect(r.pages.length, 2);
    // Page 1: cells (0,0)(0,1)(1,0)(1,1).
    expect(_boundsOf(r, 0, 'r0'),
        const JetRect(x: 10, y: 10, width: 80, height: 30));
    expect(_boundsOf(r, 0, 'r1'),
        const JetRect(x: 110, y: 10, width: 80, height: 30));
    expect(_boundsOf(r, 0, 'r2'),
        const JetRect(x: 10, y: 50, width: 80, height: 30));
    expect(_boundsOf(r, 0, 'r3'),
        const JetRect(x: 110, y: 50, width: 80, height: 30));
    // Page 2: remainder restarts at the grid origin.
    expect(_boundsOf(r, 1, 'r4'),
        const JetRect(x: 10, y: 10, width: 80, height: 30));
    expect(_boundsOf(r, 1, 'r5'),
        const JetRect(x: 110, y: 10, width: 80, height: 30));
  });

  test('page count is ceil(detailCount / cellsPerPage)', () {
    expect(
        ReportLayouter().layoutDefinition(_def(_grid), _filled(4)).pages.length,
        1);
    expect(
        ReportLayouter().layoutDefinition(_def(_grid), _filled(5)).pages.length,
        2);
  });

  test('a null columnLayout keeps the linear path byte-identical', () {
    // Linear: band0 at y=10, band1 at y=40 (stacked full width origin x=10).
    final LayoutResult r =
        ReportLayouter().layoutDefinition(_def(null), _filled(2));
    expect(r.pages.length, 1);
    expect(_boundsOf(r, 0, 'r0'),
        const JetRect(x: 10, y: 10, width: 80, height: 30));
    expect(_boundsOf(r, 0, 'r1'),
        const JetRect(x: 10, y: 40, width: 80, height: 30));
  });
}
