// Sticky fit: while a fit mode is active the canvas re-fits when the viewport
// resizes; with no fit mode, a manual zoom survives a resize.
//
// Harness note: pumpDesignerWith calls pumpDesigner which calls
// tester.binding.setSurfaceSize(kDesktopSize). When _surfaceSize is set,
// createViewConfigurationFor returns tight constraints from _surfaceSize,
// ignoring tester.view.physicalSize entirely. So post-pump resizes must also
// go through tester.binding.setSurfaceSize — that is the only API that drives
// the LayoutBuilder constraints the canvas sees.
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

void main() {
  testWidgets('fit-width re-fits when the viewport narrows (sticky)',
      (WidgetTester tester) async {
    // pumpDesignerWith sizes to kDesktopSize (1440×900); its tearDown restores
    // the surface size to null. We add no extra size tearDown here.
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    // Default mode is fit-width; the canvas fits on load.
    expect(controller.viewFitMode, JetViewFitMode.width);
    await tester.pumpAndSettle();
    final double wide = controller.viewScale;

    // Narrow the window via setSurfaceSize — the only API that actually drives
    // the LayoutBuilder constraints while a setSurfaceSize override is active.
    await tester.binding.setSurfaceSize(const Size(700, 900));
    await tester.pumpAndSettle();
    final double narrow = controller.viewScale;

    expect(narrow, lessThan(wide),
        reason: 'a narrower viewport must re-fit to a smaller width scale');
  });

  testWidgets('a manual zoom survives a resize (no fit mode)',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.pumpAndSettle();

    controller.setZoomPercent(150); // manual -> mode none
    await tester.pumpAndSettle();
    expect(controller.viewFitMode, JetViewFitMode.none);
    expect(controller.viewScale, 1.5);

    // Narrow via setSurfaceSize (same reason as above).
    await tester.binding.setSurfaceSize(const Size(700, 900));
    await tester.pumpAndSettle();

    expect(controller.viewScale, 1.5,
        reason: 'with no fit mode, a resize must not change the manual zoom');
  });
}
