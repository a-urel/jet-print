// The design surface is a real sheet of paper: it renders at the page format's
// full dimensions (A4 portrait by default), and the page-footer band is anchored
// to the bottom of the sheet (true WYSIWYG) rather than stacked right under the
// detail band. Drives the public designer only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

void main() {
  testWidgets('the page renders at the A4 portrait aspect ratio',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester);

    final Rect page = tester.getRect(find.byKey(kDesignPageKey));
    // A4 portrait: 595.28 x 841.89 → height/width ≈ 1.414. Uniform fit-to-width
    // scaling preserves the ratio.
    expect(page.height / page.width, closeTo(841.89 / 595.28, 0.02));
  });

  testWidgets('the page-footer band is anchored to the bottom of the sheet',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    // Default template bands: 0 = page header, 1 = detail, 2 = page footer.
    controller.createElement(DesignerToolType.text,
        bandIndex: 2, at: const JetOffset(0, 0));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    final Rect page = tester.getRect(find.byKey(kDesignPageKey));
    final Rect footerElement = tester.getRect(_elementFinder(id));

    // An element at the footer band's top sits in the bottom slice of the page
    // (anchored), not a third of the way down (stacked under detail).
    final double fraction = (footerElement.top - page.top) / page.height;
    expect(fraction, greaterThan(0.8),
        reason: 'footer band should be anchored to the page bottom');
  });
}
