// Properties-panel resolution of spec-030 published totals (and the spec-029
// nested-footer parent/child duality), exercised through the UI. A published
// total (e.g. customerTotal) is injected at fill time onto parent rows — it is
// NOT a schema field — so a band whose render row carries it must resolve a
// binding to it WITHOUT the "Field not found" flag, and the value picker must
// offer it. Public API only (mirrors band_collection_binding_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const String _unresolvedMsg = 'Field not found in the data source';

/// customers ▸ orders — real fields only; customerTotal is a published total
/// (orders publishes it onto the customer/root rows at fill time), NOT a field.
const JetDataSchema _schema = JetDataSchema(
  name: 'Customers',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('orderNo', type: JetFieldType.string),
        FieldDef('orderTotal', type: JetFieldType.double),
      ],
    ),
  ],
);

/// body.summary 'summary' (root scope) + a NestedScope 'orders' that publishes
/// customerTotal onto the root rows. The summary therefore resolves
/// customerTotal; the order detail band does NOT.
ReportDefinition _def() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(id: 'summary', type: BandType.summary, height: 40),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'orders',
              collectionField: 'orders',
              totals: <ScopeTotal>[
                ScopeTotal('customerTotal', r'SUM($F{orderTotal})'),
              ],
              children: <ScopeNode>[
                BandNode(
                    Band(id: 'orderRow', type: BandType.detail, height: 30)),
              ],
            )),
          ],
        ),
      ),
    );

Future<JetReportDesignerController> _pump(WidgetTester tester) async {
  final JetReportDesignerController c =
      JetReportDesignerController(definition: _def());
  await pumpDesignerWith(tester, controller: c, dataSchema: _schema);
  return c;
}

void main() {
  testWidgets(
      'a summary {SUM([customerTotal])} no longer shows the '
      'unresolved hint', (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    // {SUM([customerTotal])} compiles to SUM($F{customerTotal}); customerTotal
    // is a published total on the root rows, not a schema field.
    c.createBoundElement(
        bandId: 'summary',
        at: const JetOffset(10, 10),
        expression: r'SUM($F{customerTotal})');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(find.text(_unresolvedMsg), findsNothing);
  });

  testWidgets('a genuinely missing field still flags on the summary band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    c.createBoundElement(
        bandId: 'summary',
        at: const JetOffset(10, 10),
        expression: r'$F{nope}');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(find.text(_unresolvedMsg), findsOneWidget);
  });

  testWidgets('the order detail band does NOT resolve customerTotal',
      (WidgetTester tester) async {
    // customerTotal is published onto the ROOT rows, not the orders rows — an
    // order-scope binding to it must still flag (SC-004).
    final JetReportDesignerController c = await _pump(tester);
    c.createBoundElement(
        bandId: 'orderRow',
        at: const JetOffset(10, 10),
        expression: r'$F{customerTotal}');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(find.text(_unresolvedMsg), findsOneWidget);
  });
}
