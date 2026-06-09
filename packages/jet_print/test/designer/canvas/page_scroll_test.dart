// The page container must be scrollable when the (paper-sized) page does not fit
// the viewport — otherwise the bottom of a full A4 sheet is unreachable. Drives
// the public designer only; asserts a real scroll viewport exists and that the
// wheel/trackpad actually scrolls it vertically.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/designer_harness.dart';

ScrollableState _vertical(WidgetTester tester) =>
    tester.stateList<ScrollableState>(
      find.descendant(
        of: find.byKey(kDesignCanvasKey),
        matching: find.byType(Scrollable),
      ),
    ).firstWhere((ScrollableState s) => s.position.axis == Axis.vertical);

void main() {
  testWidgets('the page area scrolls when the page overflows the viewport',
      (WidgetTester tester) async {
    // The default A4 portrait sheet is taller than the canvas at fit-to-width.
    await pumpDesignerWith(tester);

    expect(_vertical(tester).position.maxScrollExtent, greaterThan(0),
        reason: 'an overflowing paper-sized page must be scrollable');
  });

  testWidgets('a mouse wheel scrolls the page vertically',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester);
    expect(_vertical(tester).position.pixels, 0);

    final Offset center = tester.getCenter(find.byKey(kDesignCanvasKey));
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();

    expect(_vertical(tester).position.pixels, greaterThan(0),
        reason: 'the page must scroll down on a wheel signal');
  });

  testWidgets('a two-finger trackpad gesture scrolls the page vertically',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester);
    expect(_vertical(tester).position.pixels, 0);

    // A trackpad pan gesture (PointerPanZoom), not a scroll signal — this is how
    // macOS reports two-finger trackpad scrolling.
    final Offset center = tester.getCenter(find.byKey(kDesignCanvasKey));
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
        pointer.panZoomUpdate(center, pan: const Offset(0, -300)));
    await tester.pump();
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();

    expect(_vertical(tester).position.pixels, greaterThan(0),
        reason: 'two-finger trackpad scrolling must move the page');
  });
}
