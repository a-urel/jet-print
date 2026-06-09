// Properties panel editor test (model-driven, T072).
//
// The Properties tab is a context-aware inspector bound to the controller:
//  * a single selected element → editable X/Y/W/H (setGeometry) and, for a text
//    element, its text (setText); every edit is one undoable step;
//  * a selected band → editable height (setBandHeight);
//  * the selected report → read-only page info;
//  * nothing / a multi-selection → a friendly empty state.
// The fields reflect the live model (a canvas move updates them).
//
// Drives the public `JetReportDesigner` only (Properties reached via its tab).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';
Finder _emptyHint = find.byKey(const ValueKey<String>('$_p.empty'));
Finder _field(String name) => find.byKey(ValueKey<String>('$_p.field.$name'));
Finder _editable(String name) =>
    find.descendant(of: _field(name), matching: find.byType(EditableText));
Finder _valueIn(String name, String text) =>
    find.descendant(of: _field(name), matching: find.text(text));

JetRect _bounds(JetReportDesignerController c, String id) => c.template.bands
    .expand((ReportBand b) => b.elements)
    .firstWhere((ReportElement e) => e.id == id)
    .bounds;

String _text(JetReportDesignerController c, String id) => (c.template.bands
        .expand((ReportBand b) => b.elements)
        .firstWhere((ReportElement e) => e.id == id) as TextElement)
    .text;

Future<void> _openProperties(WidgetTester tester) async {
  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<String> _addText(WidgetTester tester, JetReportDesignerController c,
    {JetOffset at = const JetOffset(20, 30)}) async {
  c.createElement(DesignerToolType.text, bandIndex: 1, at: at);
  final String id = c.selection.singleOrNull!;
  await tester.pumpAndSettle();
  return id;
}

void main() {
  group('properties — empty state', () {
    testWidgets('shows a hint and no geometry fields when nothing is selected',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);
      await _openProperties(tester);

      expect(_emptyHint, findsOneWidget);
      expect(_field('x'), findsNothing);
    });
  });

  group('properties — element', () {
    testWidgets('reflects the selected element geometry',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      await _addText(tester, c); // bounds (20, 30, 144, 18)

      expect(_valueIn('x', '20'), findsOneWidget);
      expect(_valueIn('y', '30'), findsOneWidget);
      expect(_valueIn('width', '144'), findsOneWidget);
      expect(_valueIn('height', '18'), findsOneWidget);
    });

    testWidgets('editing X commits to the model as one undoable step',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);

      await tester.enterText(_editable('x'), '60');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_bounds(c, id).x, 60);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(_bounds(c, id).x, 20);
    });

    testWidgets('the width stepper bumps the size by one',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);
      final double before = _bounds(c, id).width;

      await tester.tap(find.descendant(
          of: _field('width'), matching: find.byIcon(LucideIcons.chevronUp)));
      await tester.pumpAndSettle();

      expect(_bounds(c, id).width, greaterThan(before));
    });

    testWidgets('a text element exposes an editable text field',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);

      expect(_field('text'), findsOneWidget);
      await tester.enterText(_editable('text'), 'Hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_text(c, id), 'Hello');
    });

    testWidgets('a non-text element has no text field',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.createElement(DesignerToolType.shape,
          bandIndex: 1, at: const JetOffset(10, 10));
      await tester.pumpAndSettle();

      expect(_field('x'), findsOneWidget); // geometry still shown
      expect(_field('text'), findsNothing);
    });

    testWidgets('the fields reflect a model change made elsewhere',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      final String id = await _addText(tester, c);
      expect(_valueIn('x', '20'), findsOneWidget);

      c.setGeometry(id, x: 88); // e.g. a canvas drag / nudge
      await tester.pumpAndSettle();
      expect(_valueIn('x', '88'), findsOneWidget);
    });
  });

  group('properties — band & report', () {
    testWidgets('a selected band exposes an editable height',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectBand(1); // detail, height 200
      await tester.pumpAndSettle();

      expect(_valueIn('bandHeight', '200'), findsOneWidget);
      await tester.enterText(_editable('bandHeight'), '260');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.template.bands[1].height, 260);
    });

    testWidgets('the selected report shows read-only info, no geometry fields',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openProperties(tester);
      c.selectReport();
      await tester.pumpAndSettle();

      expect(_field('x'), findsNothing);
      expect(
        find.descendant(
            of: find.byKey(kRightPanelKey), matching: find.text('Report')),
        findsOneWidget,
      );
    });
  });
}
