// Verifies that name-typed binding fields (_BindingField) display the stored
// bare field name wrapped in brackets ([fieldName]) while keeping the stored
// collectionField as the bare name.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

void main() {
  testWidgets('the list collection binding displays [lines], stores bare lines',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await openPropertiesTab(tester);
    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');
    await tester.pumpAndSettle();

    final ShadInput input = tester.widget<ShadInput>(find.byKey(
        const ValueKey<String>(
            'jet_print.designer.properties.field.bandCollection')));
    expect(input.controller!.text, '[lines]',
        reason: 'the binding field shows the bracketed shorthand');
    expect(
        c.definition.body.root.children
            .whereType<NestedScope>()
            .single
            .scope
            .collectionField,
        'lines',
        reason: 'the stored value stays the bare field name');
  });
}
