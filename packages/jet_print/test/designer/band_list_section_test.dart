// Widget test: a detail band's inspector surfaces the list it iterates — a
// schema picker for a nested list, a read-only label for the root, and an
// unbound warning when a nested list has no collection field.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

void main() {
  testWidgets(
      'root detail band shows the read-only main-dataset label, no picker',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await openPropertiesTab(tester);

    c.selectBand(firstDetailBandId(c));
    await tester.pumpAndSettle();

    expect(find.text('Main dataset (root)'), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.properties.field.bandCollection')),
        findsNothing);
  });

  testWidgets(
      'nested-list detail band shows the bound collection in a picker field',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await openPropertiesTab(tester);

    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');
    // createListWithBand selects the new detail band.
    await tester.pumpAndSettle();

    final Finder field = find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.bandCollection'));
    expect(field, findsOneWidget);
  });

  testWidgets('an unbound nested list warns inline',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await openPropertiesTab(tester);

    c.createListWithBand(c.definition.body.root.id); // no collectionField
    await tester.pumpAndSettle();

    expect(
        find.text('List is not bound to a collection field'), findsOneWidget);
  });
}
