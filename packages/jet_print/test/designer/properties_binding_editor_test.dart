// Properties binding editor (US2 / FR-009, FR-011, FR-012).
//
// The Properties inspector binds the selected element: typing a field reference
// or a full expression sets the binding; the clear affordance reverts it to
// static. Public API only; drives the editor as a user would.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const ValueKey<String> _bindingKey =
    ValueKey<String>('jet_print.designer.properties.field.binding');

TextElement _text(JetReportDesignerController c, String id) => c.template.bands
    .expand((ReportBand b) => b.elements)
    .whereType<TextElement>()
    .firstWhere((TextElement e) => e.id == id);

Future<String> _selectedTextElement(
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

void main() {
  testWidgets('typing a field reference binds the element; clear reverts it', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedTextElement(tester, c);

    await tester.enterText(find.byKey(_bindingKey), r'$F{customerName}');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_text(c, id).expression, r'$F{customerName}');

    await tester.tap(find.bySemanticsLabel('Clear binding'));
    await tester.pumpAndSettle();
    expect(_text(c, id).expression, isNull);
  });

  testWidgets('accepts a free-form expression', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedTextElement(tester, c);

    await tester.enterText(find.byKey(_bindingKey), r'upper($F{customerName})');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_text(c, id).expression, r'upper($F{customerName})');
  });
}
