// Grid-on surface golden (spec 015-grid-snap-tools, T023 / Constitution IV).
//
// Locks the appearance of the visible 5 mm alignment grid drawn as backmost
// design-time chrome: same representative elements as design_surface_test, but
// with the grid ON at 100% zoom. This is a NEW golden — the grid-off surface
// goldens are unchanged. Regenerate intentional changes with
// `flutter test --update-goldens`.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

void main() {
  testWidgets('the design surface with the grid on matches its golden',
      (WidgetTester tester) async {
    // Rulers off (as in the grid-off surface golden) to isolate the grid; grid
    // on (the default) is what this golden pins.
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, rulers: false);
    c.setViewScale(1.0); // 100% zoom — one grid cell == 5 mm on screen
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(24, 24));
    final String textId = c.selection.singleOrNull!;
    c.createElement(DesignerToolType.shape,
        bandIndex: 1, at: const JetOffset(24, 70));
    c.createElement(DesignerToolType.image,
        bandIndex: 1, at: const JetOffset(220, 24));
    c.createElement(DesignerToolType.barcode,
        bandIndex: 1, at: const JetOffset(220, 70));
    c.select(textId);
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(kDesignCanvasKey),
      matchesGoldenFile('design_surface_grid_light.png'),
    );
  });
}
