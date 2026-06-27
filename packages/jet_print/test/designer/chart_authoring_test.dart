// Chart authoring widget smoke tests.
//
// Verifies the full Properties panel integration for a ChartElement: the type
// picker renders, the collection-field picker lists in-scope collections, and
// editing the value expression updates the element via setChartOptions.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

// --- Stable panel keys (must match properties_panel.dart '$_p' prefix) --------
const String _p = 'jet_print.designer.properties';

ValueKey<String> _chartTypeKey(String id) => ValueKey<String>('$_p.chart.$id');
ValueKey<String> _chartValueKey(String id) =>
    ValueKey<String>('$_p.field.chartValue.$id');
ValueKey<String> _chartCollectionKey(String id) =>
    ValueKey<String>('$_p.field.chartCollection.$id');
ValueKey<String> _chartCollectionPickKey(String id) =>
    ValueKey<String>('$_p.field.chartCollection.pick.$id');

// --- Fixtures -----------------------------------------------------------------

/// A schema with a top-level collection field "months" so the chart's
/// collection picker has something to offer.
const JetDataSchema _schema = JetDataSchema(
  name: 'Sales',
  fields: <FieldDef>[
    FieldDef('title', type: JetFieldType.string),
    FieldDef(
      'months',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('month', type: JetFieldType.string),
        FieldDef('revenue', type: JetFieldType.double),
      ],
    ),
  ],
);

/// A document with one detail band holding a ChartElement 'c1'.
ReportDefinition _docWithChart() => const ReportDefinition(
      name: 'Chart authoring test',
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
                  bounds: JetRect(x: 10, y: 10, width: 200, height: 130),
                  chartType: ChartType.bar,
                  collectionField: 'months',
                  valueExpression: r'$F{revenue}',
                ),
              ],
            )),
          ],
        ),
      ),
    );

ChartElement _chart(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .whereType<ChartElement>()
        .first;

// --- Helpers ------------------------------------------------------------------

Future<JetReportDesignerController> _pump(
  WidgetTester tester, {
  JetDataSchema? schema,
}) async {
  final JetReportDesignerController c = JetReportDesignerController(
    definition: _docWithChart(),
  );
  await pumpDesignerWith(tester, controller: c, dataSchema: schema);
  // Select the chart element so the Properties panel shows it.
  c.select('c1');
  await tester.pumpAndSettle();
  await openPropertiesTab(tester);
  return c;
}

// --- Tests --------------------------------------------------------------------

void main() {
  testWidgets('chart properties panel renders the chart-type control',
      (WidgetTester tester) async {
    await _pump(tester);
    // The KeyedSubtree wrapping the chart section uses _chartTypeKey.
    expect(find.byKey(_chartTypeKey('c1')), findsOneWidget);
  });

  testWidgets(
      'chart properties panel renders the collection-field picker '
      'when a schema is attached', (WidgetTester tester) async {
    await _pump(tester, schema: _schema);
    // The collection BindingField input is present.
    expect(find.byKey(_chartCollectionKey('c1')), findsOneWidget);
    // A schema is attached, so a picker button should render.
    expect(find.byKey(_chartCollectionPickKey('c1')), findsOneWidget);
  });

  testWidgets('chart properties panel renders the value expression field',
      (WidgetTester tester) async {
    await _pump(tester);
    expect(find.byKey(_chartValueKey('c1')), findsOneWidget);
  });

  testWidgets('entering a value expression updates the element',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);

    // Clear and enter a new expression in the value field.
    await tester.enterText(find.byKey(_chartValueKey('c1')), r'$F{profit}');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_chart(c).valueExpression, r'$F{profit}');
  });

  testWidgets('toolbox has a chart tool button', (WidgetTester tester) async {
    final JetReportDesignerController c = JetReportDesignerController(
      definition: _docWithChart(),
    );
    await pumpDesignerWith(tester, controller: c);

    expect(
      find.byKey(const ValueKey<String>('jet_print.designer.tool.chart')),
      findsOneWidget,
    );
  });

  testWidgets(
      'clicking chart toolbox button inserts a ChartElement into the first band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = JetReportDesignerController(
      definition: const ReportDefinition(
        name: 'Empty',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(id: 'detail', type: BandType.detail, height: 200)),
            ],
          ),
        ),
      ),
    );
    await pumpDesignerWith(tester, controller: c);

    await tester.tap(
        find.byKey(const ValueKey<String>('jet_print.designer.tool.chart')));
    await tester.pumpAndSettle();

    final elements = c.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .elements;
    expect(elements.whereType<ChartElement>(), hasLength(1));
    expect(elements.first, isA<ChartElement>());
  });
}
