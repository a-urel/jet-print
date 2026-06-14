// US6 zoom / pan / fit (T074 / SC-006 / FR-020): the canvas renders at the
// controller's view scale (so placement/hit-testing stay pointer-accurate),
// zoom clamps, and fit-to-width recenters.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

void main() {
  test('zoom clamps to 25%–400%', () {
    final JetReportDesignerController c = JetReportDesignerController();
    c.setViewScale(100);
    expect(c.viewScale, 4.0);
    c.setViewScale(0.001);
    expect(c.viewScale, 0.25);
    c.zoomIn();
    expect(c.viewScale, greaterThan(0.25));
    c.dispose();
  });

  testWidgets('elements render at the view scale (pointer-accurate placement)',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.barcode,
        bandId: 'detail', at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    final double base = controller.viewScale;
    final Rect r1 = tester.getRect(_elementFinder(id));

    controller.setViewScale(base * 2);
    await tester.pumpAndSettle();
    final Rect r2 = tester.getRect(_elementFinder(id));

    // Doubling the zoom doubles the element's on-screen size: the transform is
    // applied consistently, so a drop at a screen point maps to the same page
    // point at any zoom.
    expect(r2.width, closeTo(r1.width * 2, 1.0));
    expect(r2.height, closeTo(r1.height * 2, 1.0));
  });

  testWidgets('fit-to-width recenters after zooming out',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    controller.setViewScale(0.25); // zoom way out
    await tester.pumpAndSettle();
    final double small = tester.getRect(_elementFinder(id)).width;

    controller.fitToView();
    await tester.pumpAndSettle();
    final double fitted = tester.getRect(_elementFinder(id)).width;

    expect(fitted, greaterThan(small)); // fit zoomed the page back up to width
  });
}
