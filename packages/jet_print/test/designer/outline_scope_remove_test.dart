// Widget test: a nested list scope can be removed from the Outline (the trash
// affordance that bands have, now on List rows too), and the "Add list" menu
// stops offering a collection that already has a child list — so redundant,
// un-removable "List: <field>" nodes can neither be created nor get stuck.
import 'package:flutter/gestures.dart';
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

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

// shadcn submenus open on hover; move a synthetic mouse over the item and wait
// past its show delay.
Future<void> _hover(WidgetTester tester, String key) async {
  final TestGesture g =
      await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  addTearDown(g.removePointer);
  await g.moveTo(tester.getCenter(find.byKey(ValueKey<String>(key))));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Future<void> _openOutline(WidgetTester tester) async {
  await tester.tap(find.text('Outline').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a nested List row has a remove action that deletes the scope',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');
    await _openOutline(tester);

    final String scopeId = c.definition.body.root.children
        .whereType<NestedScope>()
        .single
        .scope
        .id;
    await _tapKey(tester, 'jet_print.designer.outline.scope.$scopeId.remove');

    expect(c.definition.body.root.children.whereType<NestedScope>(), isEmpty,
        reason: 'the trash affordance removes the List scope');
    expect(find.text('List: lines'), findsNothing);
  });

  testWidgets('"Add list" stops offering a collection already bound to a list',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.list');

    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.root.add.list.field.lines')),
        findsNothing,
        reason:
            'the only collection is already bound, so it is not re-offered');
    // Adding again is impossible → no duplicate "List: lines" can form.
    expect(
        c.definition.body.root.children.whereType<NestedScope>(), hasLength(1));
  });
}
