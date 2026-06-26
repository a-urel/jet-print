// Outline rename test (Task 8 — T071 follow-up).
//
// Verifies that double-tapping a band row or an element row in the Outline tree
// starts an inline rename, and that the committed name is reflected in the model
// and the display label.
//
// Harness mirrors outline_tree_test.dart exactly (same keys, same pump helper).
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

Key _bandRow(String id) =>
    ValueKey<String>('jet_print.designer.outline.band.$id');
Key _elementRow(String id) =>
    ValueKey<String>('jet_print.designer.outline.element.$id');

Finder _inPanel(Finder matcher) =>
    find.descendant(of: find.byKey(kRightPanelKey), matching: matcher);

Future<void> _openOutline(WidgetTester tester) async {
  final Finder tab = find.text('Outline');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Double-tap at the centre of [finder] within the double-tap window (50 ms
/// between taps — mirrors the canvas `_doubleTapAt` helper).
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  final Offset centre = tester.getCenter(finder);
  await tester.tapAt(centre);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(centre);
  await tester.pumpAndSettle();
}

void main() {
  group('outline rename (double-tap)', () {
    testWidgets('double-tap element row starts inline edit and commits name',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openOutline(tester);

      // Create a text element with text 'Subtotal' (no name set).
      final String bandId = firstDetailBandId(c);
      c.createElement(DesignerToolType.text,
          bandId: bandId, at: const JetOffset(10, 10));
      final String elementId = c.selection.singleOrNull!;
      // Set the text content so elementDisplayLabel returns 'Subtotal'.
      c.setText(elementId, 'Subtotal');
      await tester.pumpAndSettle();

      // The element row label shows 'Subtotal'.
      expect(
        _inPanel(find.text('Subtotal')),
        findsOneWidget,
      );

      // Double-tap the element row label to start inline editing.
      await _doubleTap(tester, find.byKey(_elementRow(elementId)));

      // Type the new name and submit.
      await tester.enterText(find.byType(TextField), 'Totals');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The element should now have name 'Totals' in the model.
      final ReportElement element = c.definition.body.root.children
          .whereType<BandNode>()
          .expand((BandNode n) => n.band.elements)
          .firstWhere((ReportElement e) => e.id == elementId);
      expect(element.name, 'Totals');

      // The label in the Outline row should now show 'Totals'.
      expect(
        _inPanel(find.text('Totals')),
        findsOneWidget,
      );
    });

    testWidgets('double-tap band row starts inline edit and commits name',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openOutline(tester);

      // Double-tap the detail band row label to start inline editing.
      await _doubleTap(tester, find.byKey(_bandRow('detail')));

      // Type the new name and submit.
      await tester.enterText(find.byType(TextField), 'Line items');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The detail band should now have name 'Line items' in the model.
      final Band detailBand = c.definition.body.root.children
          .whereType<BandNode>()
          .firstWhere((BandNode n) => n.band.id == 'detail')
          .band;
      expect(detailBand.name, 'Line items');

      // The label in the Outline should now show 'Line items'.
      expect(
        _inPanel(find.text('Line items')),
        findsOneWidget,
      );
    });
  });
}
