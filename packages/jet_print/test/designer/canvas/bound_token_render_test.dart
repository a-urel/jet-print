// Bound-token render golden (US2 / FR-010, FR-013, FR-014; Constitution IV).
//
// Pins how the canvas paints data-bound elements at design time: a bound text
// element shows its field TOKEN (e.g. `[customerName]`) — not a resolved value —
// emitted through the SHARED render pipeline, and a field-bound image shows the
// image placeholder. Public API only; regenerate with `--update-goldens`.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

void main() {
  testWidgets('bound text shows a token and a bound image a placeholder', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);

    // A data-bound text element (token-rendered) and a field-bound image.
    c.createBoundElement(
      bandIndex: 1,
      at: const JetOffset(24, 24),
      expression: r'$F{customerName}',
    );
    c.createElement(DesignerToolType.image,
        bandIndex: 1, at: const JetOffset(24, 70));
    c.setImageField(c.selection.singleOrNull!, 'logo');
    c.clearSelection(); // keep selection chrome out of the golden
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(kDesignCanvasKey),
      matchesGoldenFile('bound_token_surface_light.png'),
    );
  });
}
