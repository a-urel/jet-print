// A chart whose serialized chartType this build does not know keeps that name
// through unrelated edits, and loses it only on a deliberate type pick — the
// same contract as ShapeElement.unknownForm.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

const ReportDefinition _fixture = ReportDefinition(
  name: 'Newer',
  page: PageFormat.a4Portrait,
  body: ReportBody(
    root: DetailScope(
      id: 'root',
      children: <ScopeNode>[
        BandNode(Band(
          id: 'detail',
          type: BandType.detail,
          height: 200,
          elements: <ReportElement>[
            ChartElement(
              id: 'c1',
              bounds: JetRect(x: 0, y: 0, width: 100, height: 80),
              chartType: ChartType.line,
              collectionField: 'months',
              valueExpression: r'$F{revenue}',
            ),
          ],
        )),
      ],
    ),
  ),
);

/// [_fixture] as a newer build would write it: its chart names a type this
/// build does not know.
String _newerJson() => JetReportFormat.encodeDefinitionJson(_fixture)
    .replaceFirst('"chartType":"line"', '"chartType":"area"');

ChartElement _chart(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .whereType<ChartElement>()
        .single;

void main() {
  late JetReportDesignerController c;
  setUp(() => c = JetReportDesignerController()
    ..open(JetReportFormat.decodeDefinitionJson(_newerJson())));
  tearDown(() => c.dispose());

  test('the fixture really names an unknown type', () {
    expect(_newerJson(), contains('"chartType":"area"'));
  });

  test('an unrelated edit preserves the unknown chart type', () {
    expect(_chart(c).unknownChartType, 'area');
    c.setChartOptions('c1', title: 'Revenue');
    expect(_chart(c).unknownChartType, 'area');
  });

  test('a deliberate type pick clears it, even picking bar', () {
    c.setChartOptions('c1', chartType: ChartType.bar);
    expect(_chart(c).chartType, ChartType.bar);
    expect(_chart(c).unknownChartType, isNull);
  });
}
