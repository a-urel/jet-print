// US4 shift-click multi-select (T055 / acceptance US4.1).
//
// NOTE: the marquee (rubber-band) drag is implemented in the canvas
// (`_handlePanStart`/`_handlePanEnd` → `selectElements` over enclosed elements),
// but a faithful widget test of it is omitted here: flutter_test's synthetic
// pan over the canvas-level gesture detector is too sensitive to step
// coalescing and fit-to-width coordinates to assert reliably. The enclose
// primitive is straightforward and the controller's `selectElements` is covered
// by the bulk-commands tests; shift-click below covers interactive multi-select.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

void main() {
  testWidgets('shift-click toggles an element in and out of the selection',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    final String first = controller.selection.singleOrNull!;
    controller.createElement(DesignerToolType.barcode,
        bandIndex: 1, at: const JetOffset(20, 120));
    await tester.pumpAndSettle();
    final String second = controller.selection.singleOrNull!;

    // Only `second` is selected. Shift-click `first` → both selected.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(tester.getCenter(_elementFinder(first)));
    await tester.pumpAndSettle();
    expect(controller.selection.length, 2);

    // Shift-click `first` again → removed.
    await tester.tapAt(tester.getCenter(_elementFinder(first)));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(controller.selection.contains(first), isFalse);
    expect(controller.selection.contains(second), isTrue);
  });
}
