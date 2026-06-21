// US4 multi-select: shift-click and marquee (rubber-band) drag.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

void main() {
  testWidgets('dragging on the empty canvas marquee-selects enclosed elements',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(40, 20));
    await tester.pumpAndSettle();
    controller.createElement(DesignerToolType.shape,
        bandId: 'detail', at: const JetOffset(40, 70));
    await tester.pumpAndSettle();
    controller.clearSelection();
    await tester.pump();
    expect(controller.selection.isEmpty, isTrue);

    // Map page points to global coordinates (the page may be scrolled/scaled).
    final Offset pageTopLeft = tester.getTopLeft(find.byKey(kDesignPageKey));
    final double s = controller.viewScale;
    Offset at(double px, double py) => pageTopLeft + Offset(px * s, py * s);

    // Rubber-band from an empty spot (left margin). The first move stays in the
    // empty margin so the drag is recognized as a marquee (not a move starting
    // on an element); later moves grow it to enclose both elements. Marquee is
    // the MOUSE/desktop behavior — under touch an empty-canvas drag pans the
    // viewport instead (see the touch test below), so drive a mouse pointer.
    final TestGesture gesture =
        await tester.startGesture(at(10, 100), kind: PointerDeviceKind.mouse);
    await gesture.moveTo(at(20, 112));
    await tester.pump();
    await gesture.moveTo(at(140, 190));
    await tester.pump();
    await gesture.moveTo(at(260, 260));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection.length, 2,
        reason: 'the marquee should select both enclosed elements');
  });

  testWidgets(
      'under touch, an empty-canvas drag pans the viewport (no marquee select)',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(40, 20));
    await tester.pumpAndSettle();
    controller.createElement(DesignerToolType.shape,
        bandId: 'detail', at: const JetOffset(40, 70));
    await tester.pumpAndSettle();
    controller.clearSelection();
    await tester.pump();

    final Offset pageTopLeft = tester.getTopLeft(find.byKey(kDesignPageKey));
    final double s = controller.viewScale;
    Offset at(double px, double py) => pageTopLeft + Offset(px * s, py * s);

    // The SAME drag that marquee-selects under a mouse must NOT select anything
    // under touch — it pans the page instead (the natural mobile gesture).
    final TestGesture gesture =
        await tester.startGesture(at(10, 100), kind: PointerDeviceKind.touch);
    await gesture.moveTo(at(20, 112));
    await tester.pump();
    await gesture.moveTo(at(140, 190));
    await tester.pump();
    await gesture.moveTo(at(260, 260));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection.isEmpty, isTrue,
        reason: 'a touch empty-drag pans, it does not marquee-select');
  });

  testWidgets('shift-click toggles an element in and out of the selection',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(20, 20));
    final String first = controller.selection.singleOrNull!;
    controller.createElement(DesignerToolType.barcode,
        bandId: 'detail', at: const JetOffset(20, 120));
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
