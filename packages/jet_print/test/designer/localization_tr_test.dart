// Turkish localization widget test (US4 / FR-016, SC-007).
//
// In its own file (isolate) by design — see the note in localization_test.dart:
// switching between two non-English CLDR locales in one isolate leaves the later
// tree unbuilt, so each non-English locale is verified in isolation.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/designer_harness.dart';

void main() {
  testWidgets('Turkish captions render under the tr locale', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('tr'));

    // Assert on ASCII-only Turkish tokens to keep the match free of any
    // Unicode-normalization fragility in test sources (the accented captions
    // such as "Adsız rapor" render correctly; these tokens are unambiguous).
    // The toolbox is icon-only now, so assert on visible top-bar/tab captions.
    expect(find.text('Kaydet'), findsWidgets); // Save (top-bar action)
    expect(find.text('Anahat'), findsWidgets); // Outline (tab)
    // Real translation applied — the English captions are gone.
    expect(find.text('Untitled report'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Data Source'), findsNothing);

    // Band-type badges on the canvas are localized too. Scoped to the canvas
    // (independent of the Outline panel) and asserted on ASCII-only Turkish
    // tokens, per this file's convention.
    Finder onCanvas(String text) => find.descendant(
          of: find.byKey(kDesignCanvasKey),
          matching: find.text(text),
        );
    expect(onCanvas('Detay'), findsOneWidget); // Detail
    expect(onCanvas('Sayfa Alt Bilgisi'), findsOneWidget); // Page Footer
  });
}
