// German localization widget test (US4 / FR-016, SC-007).
//
// In its own file (isolate) by design — see the note in localization_test.dart:
// switching between two non-English CLDR locales in one isolate leaves the later
// tree unbuilt, so each non-English locale is verified in isolation.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

    // German has the longest chrome captions; the layout must accommodate them
    // (wrap/ellipsize) without clipping adjacent controls — no overflow recorded
    // (longer-text edge case / T037).
    expect(tester.takeException(), isNull);
  });
}
