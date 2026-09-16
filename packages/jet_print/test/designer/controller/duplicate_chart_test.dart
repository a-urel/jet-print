// Duplicate / copy-paste of a ChartElement through the designer controller.
//
// Regression: the designer's clone path round-trips an element through the
// built-in element codecs (`cloneElement`), and `chart` was registered only in
// the render-time pairing (`registerBuiltInElementTypes`), never in
// `registerBuiltInElementCodecs`. Duplicating a chart therefore threw
// `Bad state: No ElementCodec registered for type "chart"`.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _fixture() => const ReportDefinition(
      name: 'Charted',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 300,
              elements: <ReportElement>[
                ChartElement(
                  id: 'chart1',
                  bounds: JetRect(x: 10, y: 10, width: 200, height: 120),
                  chartType: ChartType.bar,
                  collectionField: 'months',
                  categoryExpression: r'$F{label}',
                  valueExpression: r'$F{revenue}',
                  title: 'Revenue',
                ),
              ],
            )),
          ],
        ),
      ),
    );

List<ReportElement> _els(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<BandNode>().first.band.elements;

JetReportDesignerController _open() =>
    JetReportDesignerController()..open(_fixture());

void main() {
  test('duplicate clones a chart, preserving every authored field', () {
    final JetReportDesignerController c = _open()..select('chart1');
    c.duplicate();

    final List<ReportElement> els = _els(c);
    expect(els.length, 2);
    final ChartElement original = els[0] as ChartElement;
    final ChartElement copy = els[1] as ChartElement;
    expect(copy.id, isNot(original.id));
    expect(copy.chartType, ChartType.bar);
    expect(copy.collectionField, 'months');
    expect(copy.categoryExpression, r'$F{label}');
    expect(copy.valueExpression, r'$F{revenue}');
    expect(copy.title, 'Revenue');
    c.dispose();
  });

  test('copy + paste clones a chart as a typed ChartElement', () {
    final JetReportDesignerController c = _open()..select('chart1');
    c.copy();
    c.paste();

    final List<ReportElement> els = _els(c);
    expect(els.length, 2);
    expect(els[1], isA<ChartElement>());
    c.dispose();
  });
}
