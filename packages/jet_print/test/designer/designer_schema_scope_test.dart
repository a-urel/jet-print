// Foundational: JetReportDesigner accepts an optional data-source structure
// (JetDataSchema) and stays drop-in without one. Public API only (this test
// stands in for an external consumer — no `package:jet_print/src/...`).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

void main() {
  testWidgets('stays drop-in: const JetReportDesigner() needs no schema',
      (WidgetTester tester) async {
    await pumpDesigner(tester);
    expect(find.byType(JetReportDesigner), findsOneWidget);
  });

  testWidgets('accepts an optional dataSchema', (WidgetTester tester) async {
    const JetDataSchema schema = JetDataSchema(
      name: 'Invoice',
      fields: <FieldDef>[
        FieldDef('customerName', type: JetFieldType.string),
        FieldDef(
          'lines',
          type: JetFieldType.collection,
          fields: <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
        ),
      ],
    );
    await pumpDesigner(
      tester,
      designer: const JetReportDesigner(dataSchema: schema),
    );
    expect(find.byType(JetReportDesigner), findsOneWidget);
  });
}
