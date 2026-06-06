// Localization widget test — English + fallback (US4 / FR-016/017, SC-007).
//
// Asserts the default English chrome and the fallback behavior for an
// unsupported locale. German and Turkish each get their OWN test file
// (localization_de_test.dart / localization_tr_test.dart) on purpose: Flutter's
// Global localizations load some locales' CLDR data through process-global async
// state, and switching between two such non-English locales within a single test
// isolate leaves the later tree unbuilt (a framework quirk — every locale
// renders correctly on its own and in the real app). One isolate per non-English
// locale sidesteps it entirely.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/designer_harness.dart';

void main() {
  testWidgets('English captions render (default locale)', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('en'));

    expect(find.text('Untitled report'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget); // top-bar action
    expect(find.text('Data Source'), findsWidgets); // tab + panel header
  });

  testWidgets('an unsupported locale falls back to English (FR-017)', (
    WidgetTester tester,
  ) async {
    // French is not shipped; Flutter resolves it to the first supported locale,
    // which is English — never a blank or a raw key.
    await pumpDesigner(tester, locale: const Locale('fr'));

    expect(find.text('Untitled report'), findsOneWidget);
    expect(find.text('Data Source'), findsWidgets);
    // No raw resource keys leak through.
    expect(find.text('reportTitlePlaceholder'), findsNothing);
    expect(find.text('tabDataSource'), findsNothing);
  });
}
