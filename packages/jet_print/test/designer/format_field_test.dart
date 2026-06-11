// The Format field (013 / T021): free-text ICU pattern + preset quick-picks,
// each a single undoable edit on TextElement.format.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const ValueKey<String> _formatKey =
    ValueKey<String>('jet_print.designer.properties.field.format');

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

void main() {
  testWidgets('the Format field is present for a text element',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _selectedText(tester, c);
    expect(find.byKey(_formatKey), findsOneWidget);
  });

  testWidgets('typing a pattern sets the format as one undoable edit',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);

    await tester.enterText(find.byKey(_formatKey), '#,##0.00');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_text(c, id).format, '#,##0.00');
    expect(c.canUndo, isTrue);
  });

  testWidgets('picking the Decimal preset fills the pattern',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);

    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.format.preset.Decimal')));
    await tester.pumpAndSettle();
    expect(_text(c, id).format, '#,##0.00');
  });

  testWidgets('picking None clears the format', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);
    c.setFormat(id, '#,##0.00');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.format.preset.None')));
    await tester.pumpAndSettle();
    expect(_text(c, id).format, isNull);
  });
}
