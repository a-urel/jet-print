// German localization widget test (US4 / FR-016, SC-007).
//
// In its own file (isolate) by design — see the note in localization_test.dart:
// switching between two non-English CLDR locales in one isolate leaves the later
// tree unbuilt, so each non-English locale is verified in isolation.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

void main() {
  testWidgets('German captions render under the de locale', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('de'));

    expect(find.text('Unbenannter Bericht'), findsOneWidget);
    expect(find.text('Vorschau'), findsOneWidget); // Preview (top-bar action)
    expect(find.text('Datenquelle'), findsWidgets); // tab + panel header
    // Real translation applied — the English captions are gone, not merely
    // falling back everywhere.
    expect(find.text('Untitled report'), findsNothing);
    expect(find.text('Data Source'), findsNothing);

    // Band-type badges on the canvas are localized too (scoped to the canvas so
    // the match is independent of the Outline panel's band names).
    Finder onCanvas(String text) => find.descendant(
          of: find.byKey(kDesignCanvasKey),
          matching: find.text(text),
        );
    expect(onCanvas('Seitenkopf'), findsOneWidget); // Page Header
    expect(onCanvas('Seitenfuß'), findsOneWidget); // Page Footer

    // German has the longest chrome captions; the layout must accommodate them
    // (wrap/ellipsize) without clipping adjacent controls — no overflow recorded
    // (longer-text edge case / T037).
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Arrange menu actions are localized under the de locale', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, locale: const Locale('de'));
    await openArrangeMenu(tester, c);

    expect(find.text('Linksbündig ausrichten'), findsOneWidget); // Align left
    expect(find.text('Vertikal verteilen'), findsOneWidget); // Distribute vert.
    expect(find.text('In den Vordergrund'), findsOneWidget); // Bring to front
    // The English captions are gone — a real translation, not a fallback.
    expect(find.text('Align left'), findsNothing);
    expect(find.text('Bring to front'), findsNothing);
  });
}
