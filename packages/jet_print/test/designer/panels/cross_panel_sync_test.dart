// Cross-panel sync (T067 / contracts §7.7 / SC-005 / US5.1–US5.3).
//
// The canvas, Outline and Properties panels share one controller, so a change in
// any of them is reflected in the others:
//  * canvas select → Outline highlights the row + Properties fills its fields;
//  * Outline row tap → the element is selected on the canvas (handles appear)
//    and scrolled into view if it was off-screen;
//  * a Properties number edit → the element moves on the canvas (undoable).
//
// Drives the public `JetReportDesigner` only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _canvasElement(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));
Finder _outlineRow(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.outline.element.$id'));
Finder _propField(String name) =>
    find.byKey(ValueKey<String>('jet_print.designer.properties.field.$name'));
final Finder _aHandle =
    find.byKey(const ValueKey<String>('jet_print.designer.handle.bottomRight'));

Future<void> _selectTab(WidgetTester tester, String caption) async {
  final Finder tab = find.text(caption);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('canvas select → Outline highlights + Properties reflects',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 30));
    final String id = c.selection.singleOrNull!;
    c.clearSelection();
    await tester.pumpAndSettle();

    // Select on the canvas by tapping the element.
    await tester.tapAt(tester.getCenter(_canvasElement(id)));
    await tester.pumpAndSettle();
    expect(c.selection.singleOrNull, id);

    // Outline highlights the matching row.
    await _selectTab(tester, 'Outline');
    final SemanticsHandle handle = tester.ensureSemantics();
    expect(tester.getSemantics(_outlineRow(id)), isSemantics(isSelected: true));
    handle.dispose();

    // Properties reflects its geometry.
    await _selectTab(tester, 'Properties');
    expect(find.descendant(of: _propField('x'), matching: find.text('20')),
        findsOneWidget);
  });

  testWidgets('Outline row tap → element selected on the canvas (handles show)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 30));
    final String id = c.selection.singleOrNull!;
    c.clearSelection();
    await tester.pumpAndSettle();
    expect(_aHandle, findsNothing);

    await _selectTab(tester, 'Outline');
    await tester.tap(_outlineRow(id));
    await tester.pumpAndSettle();

    expect(c.selection.singleOrNull, id);
    expect(_aHandle, findsOneWidget, reason: 'the canvas now shows handles');
  });

  testWidgets('Outline row tap scrolls an off-screen element into view',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    // The page footer sits at the bottom of the A4 sheet — below the fold at
    // fit-to-width — so an element there starts off-screen.
    c.createElement(DesignerToolType.text,
        bandIndex: 2, at: const JetOffset(20, 10));
    final String id = c.selection.singleOrNull!;
    c.clearSelection();
    // Creating auto-selected (and scrolled to) the element; reset to the top so
    // the footer is genuinely below the fold before we test scroll-into-view.
    c.fitToView();
    await tester.pumpAndSettle();

    final Rect canvas = tester.getRect(find.byKey(kDesignCanvasKey));
    expect(tester.getRect(_canvasElement(id)).top, greaterThan(canvas.bottom),
        reason: 'precondition: the footer element is below the viewport');

    await _selectTab(tester, 'Outline');
    await tester.tap(_outlineRow(id));
    await tester.pumpAndSettle();

    final Rect element = tester.getRect(_canvasElement(id));
    expect(element.top, lessThan(canvas.bottom));
    expect(element.bottom, greaterThan(canvas.top),
        reason: 'the element should be scrolled into the viewport');
  });

  testWidgets('Properties edit → element moves on the canvas (undoable)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 30));
    final String id = c.selection.singleOrNull!;
    await tester.pumpAndSettle();
    final double beforeLeft = tester.getRect(_canvasElement(id)).left;

    await _selectTab(tester, 'Properties');
    final Finder xEditable = find.descendant(
        of: _propField('x'), matching: find.byType(EditableText));
    await tester.enterText(xEditable, '120');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.getRect(_canvasElement(id)).left, greaterThan(beforeLeft),
        reason: 'the canvas element moved right to match the new X');
    expect(c.canUndo, isTrue);
  });
}
