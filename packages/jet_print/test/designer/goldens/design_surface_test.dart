// T080 — design-surface fidelity goldens (Constitution IV / SC-003).
//
// Pins how the interactive canvas paints REPRESENTATIVE elements (text, shape,
// image, barcode) with a selection shown — outline + resize handles — in both
// theme variants. Element appearance is emitted through the SHARED render
// pipeline (no design-time-only drawing), so a divergence there, a dropped
// theme, or a regression in the selection chrome is caught visually.
//
// Scoped to the canvas (kDesignCanvasKey) to isolate the design surface from
// the surrounding shell (covered by jet_report_designer_light_dark_test.dart).
// Regenerate intentional changes with `flutter test --update-goldens`.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

/// Seeds one of each representative element in the detail band and selects the
/// text element so the selection outline + handles are part of the golden.
Future<void> _seedSurface(
    WidgetTester tester, JetReportDesignerController c) async {
  c.createElement(DesignerToolType.text,
      bandIndex: 1, at: const JetOffset(24, 24));
  final String textId = c.selection.singleOrNull!;
  c.createElement(DesignerToolType.shape,
      bandIndex: 1, at: const JetOffset(24, 70));
  c.createElement(DesignerToolType.image,
      bandIndex: 1, at: const JetOffset(220, 24));
  c.createElement(DesignerToolType.barcode,
      bandIndex: 1, at: const JetOffset(220, 70));
  c.select(textId); // single selection → outline + eight resize handles
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the design surface matches its light golden', (
    WidgetTester tester,
  ) async {
    // Rulers are pinned by widget tests, not goldens (decision V1); pump them off
    // so this surface golden stays byte-identical and isolates element rendering.
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, rulers: false);
    await _seedSurface(tester, c);

    await expectLater(
      find.byKey(kDesignCanvasKey),
      matchesGoldenFile('design_surface_light.png'),
    );
  });

  testWidgets('the design surface matches its dark golden', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        themeMode: ThemeMode.dark, rulers: false);
    await _seedSurface(tester, c);

    await expectLater(
      find.byKey(kDesignCanvasKey),
      matchesGoldenFile('design_surface_dark.png'),
    );
  });
}
