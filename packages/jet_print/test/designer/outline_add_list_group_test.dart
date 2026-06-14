// Widget test: the Outline scope "+" menu can create a nested list and a group.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openOutline(WidgetTester tester) async {
  await tester.tap(find.text('Outline').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('scope "+" menu "Add list" creates a nested list with a detail band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add.list');

    expect(c.definition.body.root.children.whereType<NestedScope>(), hasLength(1));
  });

  testWidgets('scope "+" menu "Add group" creates a group with a header band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add.group');

    expect(c.definition.body.root.groups, hasLength(1));
    expect(c.definition.body.root.groups.single.header, isNotNull);
  });
}
