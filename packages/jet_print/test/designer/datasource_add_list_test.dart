// Widget test: a collection field in the Data Source panel offers a "+" that
// creates a list bound to that collection under the right parent scope.
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
      '"+" on a top-level collection creates a list under root bound to it',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    // Data Source tab is shown by default; tap the add-list "+" for `lines`.
    final Finder add = find.byKey(
        const ValueKey<String>('jet_print.designer.datasource.addList.lines'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final List<NestedScope> nested =
        c.definition.body.root.children.whereType<NestedScope>().toList();
    expect(nested, hasLength(1));
    expect(nested.single.scope.collectionField, 'lines');
  });
}
