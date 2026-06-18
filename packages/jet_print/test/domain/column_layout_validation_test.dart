import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/column_layout.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_validation.dart';

// 200x100 page, 10pt margins -> body 180 wide, 80 tall (no furniture).
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ReportDefinition _labels(ColumnLayout grid,
    {double bandHeight = 30, List<ReportElement> elements = const <ReportElement>[]}) =>
    ReportDefinition(
      name: 'labels',
      page: _page,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'd',
              type: BandType.detail,
              height: bandHeight,
              elements: elements,
              columnLayout: grid)),
        ]),
      ),
    );

List<Diagnostic> _errors(ReportDefinition d) => validate(d)
    .where((Diagnostic x) => x.severity == DiagnosticSeverity.error)
    .toList();
List<Diagnostic> _warnings(ReportDefinition d) => validate(d)
    .where((Diagnostic x) => x.severity == DiagnosticSeverity.warning)
    .toList();

void main() {
  const ColumnLayout ok = ColumnLayout(
      columnCount: 2, columnWidth: 80, columnSpacing: 20, rowSpacing: 10);

  test('a valid grid produces no diagnostics', () {
    expect(validate(_labels(ok)), isEmpty);
  });

  test('columnCount < 1 is an error', () {
    final List<Diagnostic> e = _errors(_labels(
        const ColumnLayout(
            columnCount: 0, columnWidth: 80, columnSpacing: 20, rowSpacing: 10)));
    expect(e.single.message, contains('columnCount'));
  });

  test('a negative dimension is an error', () {
    expect(
        _errors(_labels(const ColumnLayout(
            columnCount: 2,
            columnWidth: 80,
            columnSpacing: -1,
            rowSpacing: 10))),
        isNotEmpty);
  });

  test('grid wider than the body is an error', () {
    // 3 * 80 + 2*20 = 280 > 180.
    final List<Diagnostic> e = _errors(_labels(const ColumnLayout(
        columnCount: 3, columnWidth: 80, columnSpacing: 20, rowSpacing: 10)));
    expect(e.single.message, contains('wider than'));
  });

  test('a label taller than the body is an error', () {
    final List<Diagnostic> e = _errors(_labels(ok, bandHeight: 90));
    expect(e.single.message, contains('taller than'));
  });

  test('an element past columnWidth warns (overflow)', () {
    final List<Diagnostic> w = _warnings(_labels(ok, elements: <ReportElement>[
      ShapeElement(
          id: 's',
          bounds: const JetRect(x: 0, y: 0, width: 120, height: 30),
          kind: ShapeKind.rectangle),
    ]));
    expect(w.single.message, contains('overflows cell width'));
  });

  test('columnLayout on a non-detail (furniture) band is ignored with a warning',
      () {
    final ReportDefinition def = ReportDefinition(
      name: 'x',
      page: _page,
      furniture: const PageFurniture(
        pageHeader: Band(
            id: 'ph',
            type: BandType.pageHeader,
            height: 10,
            columnLayout: ok),
      ),
      body: const ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
        BandNode(Band(id: 'd', type: BandType.detail, height: 30)),
      ])),
    );
    expect(_warnings(def).single.message, contains('ignored'));
  });

  test('columnLayout on a detail band of a non-pure body is ignored', () {
    final ReportDefinition def = ReportDefinition(
      name: 'x',
      page: _page,
      body: const ReportBody(
        title: Band(id: 't', type: BandType.title, height: 10),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'd', type: BandType.detail, height: 30, columnLayout: ok)),
        ]),
      ),
    );
    expect(_warnings(def).any((Diagnostic d) => d.message.contains('ignored')),
        isTrue);
  });
}
