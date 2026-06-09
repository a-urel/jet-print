// Master/detail designation, scope resolution, and the unresolved indicator,
// exercised through the UI (US3 / FR-015, FR-016, FR-017, FR-018). Public API.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const ValueKey<String> _bandCollectionKey =
    ValueKey<String>('jet_print.designer.properties.field.bandCollection');

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef(
      'lines',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('description', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
      ],
    ),
  ],
);

const String _unresolvedMsg = 'Field not found in the data source';

void main() {
  testWidgets('designates the selected band as collection-bound via Properties',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    c.selectBand(1); // the detail band
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    await tester.enterText(find.byKey(_bandCollectionKey), 'lines');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.template.bands[1].collectionField, 'lines');
  });

  testWidgets('flags a binding whose field is missing from the master scope',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    c.createBoundElement(
        bandIndex: 1, at: const JetOffset(20, 20), expression: r'$F{nope}');
    final String id = c.selection.singleOrNull!;
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(find.text(_unresolvedMsg), findsOneWidget); // missing field
    c.setBinding(id, r'$F{customerName}'); // a real master field
    await tester.pumpAndSettle();
    expect(find.text(_unresolvedMsg), findsNothing);
  });

  testWidgets('resolves child-scope fields and flags master/scope mismatches',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    c.setBandCollection(<int>[1], 'lines'); // band 1 iterates the lines scope
    c.createBoundElement(
        bandIndex: 1,
        at: const JetOffset(20, 20),
        expression: r'$F{description}'); // a line field
    final String id = c.selection.singleOrNull!;
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    // `description` is in the lines (child) scope → resolved.
    expect(find.text(_unresolvedMsg), findsNothing);

    // `customerName` is a master field, out of the line scope → unresolved.
    c.setBinding(id, r'$F{customerName}');
    await tester.pumpAndSettle();
    expect(find.text(_unresolvedMsg), findsOneWidget);
  });
}
