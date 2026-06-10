// Double-tapping a report object brings the Properties inspector forward and
// focuses its most relevant field — Text for a text element, X otherwise.
// In-place editing is gone (the Properties panel is the only text editor).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

final Finder _xField =
    find.byKey(const ValueKey<String>('jet_print.designer.properties.field.x'));
final Finder _textField = find.byKey(
    const ValueKey<String>('jet_print.designer.properties.field.text'));

String _textOf(JetReportDesignerController c, String id) => (c.template.bands
        .expand((ReportBand b) => b.elements)
        .firstWhere((ReportElement e) => e.id == id) as TextElement)
    .text;

bool _hasFocus(WidgetTester tester, Finder field) {
  final EditableText editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)));
  return editable.focusNode.hasFocus;
}

Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'double-tapping a text element focuses the Properties Text field; the '
      'edit commits and is undoable', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    expect(_textOf(controller, id), 'Text'); // default content

    await _doubleTapAt(tester, tester.getCenter(_elementFinder(id)));

    // No inline editor anymore; the Properties tab took over.
    expect(
        find.byKey(
            const ValueKey<String>('jet_print.designer.inlineTextEditor')),
        findsNothing);
    expect(controller.selection.singleOrNull, id);
    expect(_hasFocus(tester, _textField), isTrue);

    // The focused field edits the element's text, undoably (FR coverage that
    // the removed inline-editor test used to provide).
    await tester.enterText(_textField, 'Invoice');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_textOf(controller, id), 'Invoice');
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(_textOf(controller, id), 'Text');
  });

  testWidgets('double-tapping a shape element focuses the X field',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.shape,
        bandIndex: 1, at: const JetOffset(40, 30));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    await _doubleTapAt(tester, tester.getCenter(_elementFinder(id)));

    expect(_hasFocus(tester, _xField), isTrue);
  });

  testWidgets('a single tap selects but never switches the right panel tab',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    controller.clearSelection();
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(_elementFinder(id)));
    // Let the manual double-tap window (300 ms) lapse.
    await tester.pumpAndSettle(const Duration(milliseconds: 350));

    expect(controller.selection.singleOrNull, id); // selected…
    expect(_xField, findsNothing); // …but still on the Data Source tab
    expect(controller.pendingPropertiesFocus, isFalse);
  });

  testWidgets(
      'narrow layout: a double-tap opens the overlay and focuses the field',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester, size: kNarrowSize);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    expect(find.byKey(kRightPanelKey), findsNothing); // collapsed to the rail

    await _doubleTapAt(tester, tester.getCenter(_elementFinder(id)));

    expect(find.byKey(kRightPanelKey), findsOneWidget);
    expect(_hasFocus(tester, _textField), isTrue);
  });
}
