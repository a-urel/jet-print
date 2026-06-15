// Widget test: the Outline scope "+" menu creates a nested list, and "Add group"
// is a field submenu that creates a group bound to the picked field; with no
// scalar field in scope it is disabled (no placeholder group).
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

// A schema whose root exposes only a collection — no scalar field to group by.
const JetDataSchema _collectionsOnly = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

// A schema with no collection field anywhere — nothing for a list to bind to.
const JetDataSchema _scalarsOnly = JetDataSchema(
  name: 'Flat',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('customerName', type: JetFieldType.string),
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
// past its show delay (100ms).
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
  testWidgets('"Add list ▸ lines" creates a nested list bound to that collection',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.list');
    await _tapKey(tester,
        'jet_print.designer.outline.scope.root.add.list.field.lines');

    final List<NestedScope> nested =
        c.definition.body.root.children.whereType<NestedScope>().toList();
    expect(nested, hasLength(1));
    expect(nested.single.scope.collectionField, 'lines',
        reason: 'the list is born bound to the picked collection');
  });

  testWidgets('"Add list" creates nothing when no collection is in scope',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _scalarsOnly);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.list');

    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.root.add.list.field.invoiceNo')),
        findsNothing);
    expect(c.definition.body.root.children.whereType<NestedScope>(), isEmpty);
  });

  testWidgets('"Add group" submenu creates a group bound to the picked field',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.group');
    await _tapKey(tester,
        'jet_print.designer.outline.scope.root.add.group.field.invoiceNo');

    final List<GroupLevel> groups = c.definition.body.root.groups;
    expect(groups, hasLength(1));
    expect(groups.single.name, 'invoiceNo');
    expect(groups.single.key, r'$F{invoiceNo}');
    expect(groups.single.header, isNotNull);
  });

  testWidgets(
      '"Add group" offers no fields and creates nothing when only collections '
      'are in scope', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _collectionsOnly);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.group');

    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.root.add.group.field.description')),
        findsNothing);
    expect(c.definition.body.root.groups, isEmpty);
  });
}
