// Responsive-collapse (T011) + splitter-resize (T011a) widget tests.
//
// Below the 1024px breakpoint the right panel collapses to an icon rail with a
// visible expand affordance, and expanding restores it (FR-011/FR-014, SC-004).
// The left toolbox is a fixed icon strip and stays visible at every width. At
// desktop width the right panel is draggable down to an enforced minimum while
// the surface absorbs the freed space (FR-013).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/designer_harness.dart';

void main() {
  group('responsive collapse (narrow width)', () {
    testWidgets('the right panel collapses to a rail below the breakpoint', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester, size: kNarrowSize);

      // The right panel collapses to a rail...
      expect(find.byKey(kRightPanelRailKey), findsOneWidget);
      expect(find.byKey(kRightPanelKey), findsNothing);
      // ...while the toolbox icon strip and the surface stay visible (never
      // clipped out of view).
      expect(find.byKey(kToolboxKey), findsOneWidget);
      expect(find.byKey(kSurfaceKey), findsOneWidget);
    });

    testWidgets('tapping the rail expands the right panel', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester, size: kNarrowSize);

      await tester.tap(find.byKey(kRightPanelExpandKey));
      await tester.pumpAndSettle();
      expect(find.byKey(kRightPanelKey), findsOneWidget);
    });
  });

  group('splitter resize (desktop width)', () {
    testWidgets('dragging the splitter shrinks the right panel to its minimum',
        (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      final double rightBefore =
          tester.getSize(find.byKey(kRightPanelKey)).width;
      final double surfaceBefore =
          tester.getSize(find.byKey(kSurfaceKey)).width;

      // The divider sits at the surface/right-panel boundary; drag it hard right
      // to shrink the right panel.
      final Rect rightRect = tester.getRect(find.byKey(kRightPanelKey));
      final Offset dividerPoint = Offset(rightRect.left, rightRect.center.dy);
      await tester.dragFrom(dividerPoint, const Offset(600, 0));
      await tester.pumpAndSettle();

      final double rightAfter =
          tester.getSize(find.byKey(kRightPanelKey)).width;
      final double surfaceAfter = tester.getSize(find.byKey(kSurfaceKey)).width;

      // It shrank, the surface absorbed the freed space, and the minimum-width
      // floor stopped it well above zero (never collapses past its min).
      expect(rightAfter, lessThan(rightBefore));
      expect(surfaceAfter, greaterThan(surfaceBefore));
      expect(rightAfter, greaterThan(150));
    });
  });
}
