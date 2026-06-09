// Scroll affordances: a two-finger trackpad pan must scroll (not draw a marquee),
// and the horizontal scrollbar must be pinned to the bottom of the viewport (and
// visible) when the page is wider than the viewport. Drives the public designer.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

final Finder _marquee =
    find.byKey(const ValueKey<String>('jet_print.designer.marquee'));

final Finder _hScrollbar =
    find.byKey(const ValueKey<String>('jet_print.designer.scrollbar.horizontal'));

void main() {
  testWidgets('a two-finger trackpad scroll does not draw a marquee',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester);

    final Offset center = tester.getCenter(find.byKey(kDesignCanvasKey));
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
        pointer.panZoomUpdate(center, pan: const Offset(0, -200)));
    await tester.pump();

    expect(_marquee, findsNothing,
        reason: 'scrolling must not start a rubber-band selection');

    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();
  });

  testWidgets('the horizontal scrollbar is shown and pinned to the viewport '
      'bottom when the page is wider than the viewport',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.setViewScale(4.0); // page now far wider than the viewport
    await tester.pumpAndSettle();

    expect(_hScrollbar, findsOneWidget);

    final Rect canvas = tester.getRect(find.byKey(kDesignCanvasKey));
    final Rect bar = tester.getRect(_hScrollbar);
    expect(bar.bottom, closeTo(canvas.bottom, 1.0),
        reason: 'the horizontal scrollbar must sit at the viewport bottom');
  });
}
