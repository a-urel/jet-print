// Widget test: a scalar field in the Data Source panel offers a "+ group" that
// creates a group bound to that field under the right scope; a scalar inside a
// collection with no bound scope offers no such affordance.
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
  testWidgets('"+ group" on a top-level scalar creates a root group bound to it',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);

    final Finder add = find.byKey(const ValueKey<String>(
        'jet_print.designer.datasource.addGroup.invoiceNo'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final List<GroupLevel> groups = c.definition.body.root.groups;
    expect(groups, hasLength(1));
    expect(groups.single.name, 'invoiceNo');
    expect(groups.single.key, r'$F{invoiceNo}');
  });

  testWidgets(
      '"+ group" on a scalar under a bound collection scope creates a nested '
      'group there (not at root)', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    // Bind a list to `lines` so its scope exists to host a group.
    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');
    await tester.pumpAndSettle();
    // Creating the list may have moved the right panel off Data Source; bring
    // it back, then expand `lines` so its `description` row renders.
    await tester.tap(find.text('Data Source').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lines'));
    await tester.pumpAndSettle();

    final Finder add = find.byKey(const ValueKey<String>(
        'jet_print.designer.datasource.addGroup.description'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final NestedScope list =
        c.definition.body.root.children.whereType<NestedScope>().single;
    expect(list.scope.groups, hasLength(1),
        reason: 'the group lands on the nested lines scope');
    expect(list.scope.groups.single.key, r'$F{description}');
    expect(c.definition.body.root.groups, isEmpty,
        reason: 'nothing was added to the root scope');
  });

  testWidgets(
      'a scalar inside a collection with no bound scope offers no "+ group"',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester, dataSchema: _invoice);
    // Expand the `lines` collection so its child `description` row renders.
    await tester.tap(find.text('lines'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.datasource.addGroup.description')),
        findsNothing);
  });
}
