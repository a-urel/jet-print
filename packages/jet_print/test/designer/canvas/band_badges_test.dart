// Band-type badges (design-time chrome): every band on the canvas carries a
// small badge naming its role (Page Header / Detail / Page Footer …) — the band
// captions a report designer surfaces so authors always know which band they
// are editing. Drives the public `JetReportDesigner` only (never reaches into
// `src/`); the assertions are scoped to the canvas subtree so they never collide
// with the Outline panel's identical band names.
//
// Localized captions are verified per-locale in localization_de_test.dart /
// localization_tr_test.dart (each in its own isolate — switching between two
// non-English CLDR locales in one isolate leaves the later tree unbuilt).
import 'package:flutter_test/flutter_test.dart';

import '../support/designer_harness.dart';

/// A caption [text] that appears *inside the design canvas* (not the panels).
Finder _badge(String text) => find.descendant(
      of: find.byKey(kDesignCanvasKey),
      matching: find.text(text),
    );

void main() {
  testWidgets('labels each band of the default template', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester);

    // The default template stacks page-header / detail / page-footer; each gets
    // exactly one badge on the canvas.
    expect(_badge('Page Header'), findsOneWidget);
    expect(_badge('Detail'), findsOneWidget);
    expect(_badge('Page Footer'), findsOneWidget);
  });
}
