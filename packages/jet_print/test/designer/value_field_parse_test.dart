// The unified value field (013 / T004, replacing the old binding editor): one
// field parses literal text, [field] bindings, and { … } templates, each a
// single undoable edit, and shows a stored binding as its canvas token.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const ValueKey<String> _valueKey =
    ValueKey<String>('jet_print.designer.properties.field.value');

TextElement _text(JetReportDesignerController c, String id) => c.template.bands
    .expand((ReportBand b) => b.elements)
    .whereType<TextElement>()
    .firstWhere((TextElement e) => e.id == id);

Future<String> _selectedText(
  WidgetTester tester,
  JetReportDesignerController c,
) async {
  c.createElement(DesignerToolType.text,
      bandIndex: 1, at: const JetOffset(20, 20));
  final String id = c.selection.singleOrNull!;
  await tester.pumpAndSettle();
  await openPropertiesTab(tester);
  return id;
}

Future<void> _commit(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(_valueKey), value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a [field] token binds the element', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);
    await _commit(tester, '[customerName]');
    expect(_text(c, id).expression, r'$F{customerName}');
  });

  testWidgets('literal text makes a literal label',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);
    await _commit(tester, 'sample text');
    expect(_text(c, id).text, 'sample text');
    expect(_text(c, id).expression, isNull);
  });

  testWidgets('a { … } template compiles to a binding',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);
    await _commit(tester, '{[firstName] [lastName]}');
    expect(
        _text(c, id).expression, r'CONCAT($F{firstName}, " ", $F{lastName})');
  });

  testWidgets('an escaped bracket stays literal', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);
    await _commit(tester, r'\[draft]');
    expect(_text(c, id).text, '[draft]');
    expect(_text(c, id).expression, isNull);
  });

  testWidgets('switching bound → literal is a single undoable edit',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);
    await _commit(tester, '[customerName]');
    final bool boundUndo = c.canUndo;
    await _commit(tester, 'Paid in full');
    expect(boundUndo, isTrue);
    expect(_text(c, id).expression, isNull);
    expect(_text(c, id).text, 'Paid in full');
    // One undo reverts the literal back to the binding (single edit).
    c.undo();
    expect(_text(c, id).expression, r'$F{customerName}');
  });

  testWidgets('a bound element shows its [field] token in the value field',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);
    c.setValue(id, '[customerName]');
    await tester.pumpAndSettle();
    expect(find.text('[customerName]'), findsWidgets);
  });
}
