// US5 inline text editing (T067 / T073 / FR-019): double-click a text element
// to edit it in place; Enter commits, and the edit is undoable.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

final Finder _editor =
    find.byKey(const ValueKey<String>('jet_print.designer.inlineTextEditor'));

String _textOf(JetReportDesignerController c, String id) =>
    (c.template.bands
            .expand((ReportBand b) => b.elements)
            .firstWhere((ReportElement e) => e.id == id) as TextElement)
        .text;

void main() {
  testWidgets('double-click opens an inline editor; Enter commits, undoable',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    expect(_textOf(controller, id), 'Text'); // default content

    // Double-click the element.
    final Offset center = tester.getCenter(_elementFinder(id));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(_editor, findsOneWidget);

    // Edit and commit with the done action.
    await tester.enterText(_editor, 'Invoice');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_textOf(controller, id), 'Invoice');
    expect(_editor, findsNothing); // editor dismissed on commit
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(_textOf(controller, id), 'Text');
  });

  testWidgets('inline edit also commits when focus is lost (blur)',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    final Offset center = tester.getCenter(_elementFinder(id));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(_editor, findsOneWidget);

    await tester.enterText(_editor, 'Blurred');
    // Tap the grey margin off the paper to move focus away from the editor.
    final Offset canvasTopLeft = tester.getTopLeft(find.byKey(kDesignCanvasKey));
    await tester.tapAt(canvasTopLeft + const Offset(6, 120));
    await tester.pumpAndSettle();

    expect(_textOf(controller, id), 'Blurred');
    expect(_editor, findsNothing);
  });
}
