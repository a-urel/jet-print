// Widget test: dragging a collection field's handle onto the canvas creates a
// nested list under the drop band's scope, bound to that collection.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

void main() {
  testWidgets('dropping a collection field on the canvas creates a bound list',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);

    final Finder handle = find.byKey(
        const ValueKey<String>('jet_print.designer.datasource.dragList.lines'));
    final Offset from = tester.getCenter(handle);
    final Offset to =
        tester.getTopLeft(find.byKey(kDesignPageKey)) + const Offset(120, 60);
    await tester.drag(handle, to - from);
    await tester.pumpAndSettle();

    final List<NestedScope> nested =
        c.definition.body.root.children.whereType<NestedScope>().toList();
    expect(nested, hasLength(1));
    expect(nested.single.scope.collectionField, 'lines');
  });
}
