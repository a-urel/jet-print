// Selection chrome for the new selectable objects:
//  * a selected band shows a single vertical divider handle (no element-style
//    corner/side handles), and dragging it resizes the band's height;
//  * a selected report shows an outline only — no handles at all.
// Drives the public designer only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

final Finder _bandHandle =
    find.byKey(const ValueKey<String>('jet_print.designer.bandHandle'));

// Every element-style resize handle (keys `jet_print.designer.handle.<pos>`).
final Finder _elementHandles = find.byWidgetPredicate((Widget w) {
  final Key? k = w.key;
  return k is ValueKey<String> &&
      k.value.startsWith('jet_print.designer.handle.');
});

void main() {
  testWidgets('a selected band shows one divider handle and no element handles',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.selectBand(1);
    await tester.pumpAndSettle();

    expect(_bandHandle, findsOneWidget);
    expect(_elementHandles, findsNothing,
        reason: 'a band is not resized like an element (no redundant handles)');
  });

  testWidgets('a selected report shows no resize handles at all',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.selectReport();
    await tester.pumpAndSettle();

    expect(_bandHandle, findsNothing);
    expect(_elementHandles, findsNothing,
        reason: 'the page is a fixed format — not interactively resizable');
  });

  testWidgets('dragging a flow band\'s divider down grows its height',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.setViewScale(0.3); // whole sheet visible → handle on-screen
    controller.selectBand(1); // detail (flow band)
    await tester.pumpAndSettle();
    final double before = controller.template.bands[1].height;

    // Several steps so movement clears kPanSlop (~36px) and still leaves
    // post-recognition deltas to grow the band.
    final TestGesture g = await tester.startGesture(tester.getCenter(_bandHandle));
    for (int i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, 40));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(controller.template.bands[1].height, greaterThan(before),
        reason: 'dragging a flow band divider down increases its height');
  });

  testWidgets('dragging a footer\'s divider up grows its height',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.setViewScale(0.3);
    controller.selectBand(2); // page footer (bottom-anchored)
    await tester.pumpAndSettle();
    final double before = controller.template.bands[2].height;

    // The footer grows from its top edge, so dragging the divider UP enlarges it.
    final TestGesture g = await tester.startGesture(tester.getCenter(_bandHandle));
    for (int i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(controller.template.bands[2].height, greaterThan(before),
        reason: 'a bottom-anchored band grows when its top divider is dragged up');
  });
}
