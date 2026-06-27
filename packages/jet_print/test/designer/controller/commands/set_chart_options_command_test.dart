// SetChartOptionsCommand tests, exercised through the public controller surface.
//
// Black-box: drives only JetReportDesignerController (mirroring
// set_barcode_commands_test.dart). The command itself is an implementation
// detail — we assert via the public element API. Tests cover:
//   - field preservation (the silent-drop trap)
//   - no-op for a missing id
//   - undoability
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

const JetRect _bounds = JetRect(x: 0, y: 0, width: 200, height: 130);

ChartElement _chart({
  String id = 'c1',
  ChartType chartType = ChartType.bar,
  String collectionField = 'months',
  String valueExpression = r'$F{revenue}',
}) =>
    ChartElement(
      id: id,
      bounds: _bounds,
      chartType: chartType,
      collectionField: collectionField,
      valueExpression: valueExpression,
    );

ReportDefinition _report(List<ReportElement> elements) => ReportDefinition(
      name: 'Chart options test',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 200,
              elements: elements,
            )),
          ],
        ),
      ),
    );

JetReportDesignerController _controller(
        {ChartType chartType = ChartType.bar}) =>
    JetReportDesignerController(
      definition: _report(<ReportElement>[_chart(chartType: chartType)]),
    );

ChartElement _find(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .firstWhere((ReportElement e) => e.id == id) as ChartElement;

void main() {
  group('setChartOptions — sets named field, preserves others', () {
    test('sets chartType, preserving collectionField and valueExpression', () {
      final JetReportDesignerController c = _controller();
      c.setChartOptions('c1', chartType: ChartType.line);

      final el = _find(c, 'c1');
      expect(el.chartType, ChartType.line);
      // ALL other fields preserved (the silent-drop test):
      expect(el.collectionField, 'months');
      expect(el.valueExpression, r'$F{revenue}');
      expect(el.showAxes, true);
      expect(el.showValueLabels, false);
      expect(el.showLegend, false);
      expect(el.seriesColor, kDefaultChartColor);
      expect(el.bounds, _bounds);
      c.dispose();
    });

    test('sets collectionField and valueExpression together', () {
      final JetReportDesignerController c = _controller();
      c.setChartOptions('c1',
          collectionField: 'quarters', valueExpression: r'$F{profit}');

      final el = _find(c, 'c1');
      expect(el.collectionField, 'quarters');
      expect(el.valueExpression, r'$F{profit}');
      expect(el.chartType, ChartType.bar); // untouched
      c.dispose();
    });

    test('sets showAxes toggle, preserving all other flags', () {
      final JetReportDesignerController c = _controller();
      c.setChartOptions('c1', showAxes: false);

      final el = _find(c, 'c1');
      expect(el.showAxes, false);
      expect(el.showValueLabels, false); // untouched
      expect(el.showLegend, false); // untouched
      c.dispose();
    });

    test('sets seriesColor', () {
      const JetColor red = JetColor(0xFFFF0000);
      final JetReportDesignerController c = _controller();
      c.setChartOptions('c1', seriesColor: red);

      expect(_find(c, 'c1').seriesColor, red);
      expect(_find(c, 'c1').chartType, ChartType.bar); // preserved
      c.dispose();
    });

    test('sets categoryExpression and title', () {
      final JetReportDesignerController c = _controller();
      c.setChartOptions('c1',
          categoryExpression: r'$F{month}', title: 'Revenue by Month');

      final el = _find(c, 'c1');
      expect(el.categoryExpression, r'$F{month}');
      expect(el.title, 'Revenue by Month');
      expect(el.collectionField, 'months'); // preserved
      c.dispose();
    });
  });

  group('setChartOptions — no-op for missing id', () {
    test('missing id leaves chart element unchanged', () {
      final JetReportDesignerController c = _controller();
      c.setChartOptions('nope', chartType: ChartType.pie);

      expect(_find(c, 'c1').chartType, ChartType.bar);
      expect(_find(c, 'c1').collectionField, 'months');
      c.dispose();
    });
  });

  group('setChartOptions — undoable', () {
    test('a chart type change is undoable', () {
      final JetReportDesignerController c = _controller();
      c.setChartOptions('c1', chartType: ChartType.pie);
      expect(_find(c, 'c1').chartType, ChartType.pie);

      expect(c.canUndo, isTrue);
      c.undo();
      expect(_find(c, 'c1').chartType, ChartType.bar);
      c.dispose();
    });

    test('is exactly one undoable step per call', () {
      final JetReportDesignerController c = _controller();
      c.setChartOptions('c1', chartType: ChartType.line);
      c.setChartOptions('c1', chartType: ChartType.pie);

      c.undo();
      expect(_find(c, 'c1').chartType, ChartType.line);
      c.undo();
      expect(_find(c, 'c1').chartType, ChartType.bar);
      expect(c.canUndo, isFalse);
      c.dispose();
    });
  });
}
