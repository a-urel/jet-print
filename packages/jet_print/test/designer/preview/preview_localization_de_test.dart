// Preview chrome localization — German (011 — C11 / FR-017). One isolate per
// non-English locale (see preview_localization_support.dart).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preview_localization_support.dart';

void main() {
  testWidgets('German chrome', (WidgetTester tester) async {
    await pumpLocalizedPreview(tester, const Locale('de'), withActions: true);
    expect(find.text('Seite 1 von 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Vorherige Seite'), findsOneWidget);
    expect(find.bySemanticsLabel('Nächste Seite'), findsOneWidget);
    expect(find.bySemanticsLabel('An Breite anpassen'), findsOneWidget);
    // 012 export/print actions (FR-014).
    expect(find.bySemanticsLabel('Als PDF exportieren'), findsOneWidget);
    expect(find.bySemanticsLabel('Drucken'), findsOneWidget);
  });
}
