// Double-tapping a report object brings the Properties inspector forward and
// focuses its most relevant field — Text for a text element, X otherwise.
// In-place editing is gone (the Properties panel is the only text editor).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

final Finder _xField =
    find.byKey(const ValueKey<String>('jet_print.designer.properties.field.x'));
final Finder _textField = find
    .byKey(const ValueKey<String>('jet_print.designer.properties.field.value'));
final Finder _bandHeightField = find.byKey(
    const ValueKey<String>('jet_print.designer.properties.field.bandHeight'));

// Maps a page point (points) to a global screen offset, accounting for the
// page's position and the live zoom (mirrors band_page_select_test).
Offset Function(double, double) _pageMapper(
    WidgetTester tester, JetReportDesignerController controller) {
  final Offset pageTopLeft = tester.getTopLeft(find.byKey(kDesignPageKey));
  final double s = controller.viewScale;
  return (double px, double py) => pageTopLeft + Offset(px * s, py * s);
}

// The center of the `detail` band, in page points: below the page header,
// centered horizontally.
Offset _band1Center(JetReportDesignerController controller) {
  final PageFormat page = controller.definition.page;
  final JetEdgeInsets margins = page.margins;
  final double h0 = controller.definition.furniture.pageHeader!.height;
  final double h1 = controller.definition.body.root.children
      .whereType<BandNode>()
      .first
      .band
      .height;
  final double cx =
      margins.left + (page.width - margins.left - margins.right) / 2;
  final double cy = margins.top + h0 + h1 / 2;
  return Offset(cx, cy);
}

String _textOf(JetReportDesignerController c, String id) =>
    (c.definition.body.root.children
            .whereType<BandNode>()
            .expand((BandNode n) => n.band.elements)
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
        bandId: 'detail', at: const JetOffset(20, 20));
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
        bandId: 'detail', at: const JetOffset(40, 30));
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
        bandId: 'detail', at: const JetOffset(20, 20));
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
        bandId: 'detail', at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    expect(find.byKey(kRightPanelKey), findsNothing); // collapsed to the rail

    await _doubleTapAt(tester, tester.getCenter(_elementFinder(id)));

    expect(find.byKey(kRightPanelKey), findsOneWidget);
    expect(_hasFocus(tester, _textField), isTrue);
  });

  testWidgets('shift+double-tap is a multi-select gesture, not a focus request',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _doubleTapAt(tester, tester.getCenter(_elementFinder(id)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(controller.pendingPropertiesFocus, isFalse);
    expect(_xField, findsNothing); // right panel stays on Data Source
  });

  testWidgets(
      'double-tapping a band\'s empty area selects it and focuses the height '
      'field', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    final Offset Function(double, double) at = _pageMapper(tester, controller);
    final Offset center = _band1Center(controller);

    await _doubleTapAt(tester, at(center.dx, center.dy));

    expect(controller.selection.bandId, 'detail');
    expect(_hasFocus(tester, _bandHeightField), isTrue);
  });

  testWidgets(
      'double-tapping the report (paper, off any band) brings the Properties '
      'pane forward', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    final Offset Function(double, double) at = _pageMapper(tester, controller);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));

    // The top-left margin corner: inside the paper, inside no band.
    await _doubleTapAt(tester, at(2, 2));

    expect(controller.selection.isReport, isTrue);
    expect(controller.pendingPropertiesFocus, isFalse); // consumed
    // The Properties tab is now active, showing the report inspector — the
    // right panel switched away from Data Source. The report has no editable
    // field, so the pane simply comes forward.
    expect(find.text(l10n.reportLabel), findsOneWidget);
  });

  testWidgets(
      'double-tapping off the paper clears the selection and requests no focus',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.selectReport();
    await tester.pumpAndSettle();
    // The muted canvas margin just left of the page (off the paper). Anchored to
    // the page edge so it stays in the margin regardless of the ruler inset.
    final Offset pageTopLeft = tester.getTopLeft(find.byKey(kDesignPageKey));

    await _doubleTapAt(
        tester, Offset(pageTopLeft.dx - 8, pageTopLeft.dy + 120));

    expect(controller.selection.isEmpty, isTrue);
    expect(controller.pendingPropertiesFocus, isFalse);
  });

  testWidgets('a single tap on a band selects it but requests no focus',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    final Offset Function(double, double) at = _pageMapper(tester, controller);
    final Offset center = _band1Center(controller);

    await tester.tapAt(at(center.dx, center.dy));
    // Let the manual double-tap window (300 ms) lapse.
    await tester.pumpAndSettle(const Duration(milliseconds: 350));

    expect(controller.selection.bandId, 'detail'); // selected…
    expect(_bandHeightField, findsNothing); // …but still on Data Source
    expect(controller.pendingPropertiesFocus, isFalse);
  });
}
