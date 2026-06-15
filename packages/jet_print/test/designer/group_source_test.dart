// The group source: a rename field and a schema field-picker on the key that
// stores $F{field}; manual expression edits and a non-field (constant) key stay
// editable.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

Future<JetReportDesignerController> _withGroupSelected(
    WidgetTester tester) async {
  final JetReportDesignerController c =
      await pumpDesignerWith(tester, dataSchema: _invoice);
  c.createGroupBoundToField(
      c.definition.body.root.id, 'invoiceNo'); // selects the header band
  await openPropertiesTab(tester);
  await tester.pumpAndSettle();
  return c;
}

String _key(JetReportDesignerController c) =>
    c.definition.body.root.groups.single.key;

void main() {
  testWidgets('the group name field renames the group',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _withGroupSelected(tester);
    final Finder f = find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.groupName'));
    await tester.enterText(f, 'invoice');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.definition.body.root.groups.single.name, 'invoice');
  });

  testWidgets(
      'a non-field key shows editable and the picker stores \$F{field}',
      (WidgetTester tester) async {
    // Groups are born bound; to exercise the "non-field key stays editable"
    // path, set a constant key manually (before the first pump so the input
    // seeds with it).
    final JetReportDesignerController c = JetReportDesignerController();
    c.createGroupBoundToField(c.definition.body.root.id, 'invoiceNo');
    c.setGroupKey(c.definition.body.root.groups.single.id, '0');
    // pumpDesignerWith registers the dispose tear-down for the passed controller.
    await pumpDesignerWith(tester, controller: c, dataSchema: _invoice);
    await openPropertiesTab(tester);
    await tester.pumpAndSettle();

    final ShadInput keyInput = tester.widget<ShadInput>(find.byKey(
        const ValueKey<String>(
            'jet_print.designer.properties.field.groupKey')));
    expect(keyInput.controller!.text, '0');
    expect(keyInput.readOnly, isFalse,
        reason: 'a non-field key stays editable');

    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.groupKey.pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.groupKey.pick.invoiceNo')));
    await tester.pumpAndSettle();

    expect(_key(c), r'$F{invoiceNo}');
  });

  testWidgets('typing a raw expression updates the key (manual edit path)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _withGroupSelected(tester);
    final Finder f = find.byKey(
        const ValueKey<String>('jet_print.designer.properties.field.groupKey'));
    await tester.enterText(f, r'$F{customerName}');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_key(c), r'$F{customerName}');
  });
}
