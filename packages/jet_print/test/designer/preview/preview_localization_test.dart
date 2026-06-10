// Preview chrome localization — English + fallback (011 — C11 / FR-017).
//
// German and Turkish each get their OWN test file
// (preview_localization_de_test.dart / preview_localization_tr_test.dart),
// following the designer localization precedent: switching between two
// non-English locales within one test isolate can leave the later tree
// unbuilt (a framework quirk — every locale renders correctly on its own).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preview_localization_support.dart';

void main() {
  testWidgets('English chrome (default)', (WidgetTester tester) async {
    await pumpLocalizedPreview(tester, const Locale('en'));
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous page'), findsOneWidget);
    expect(find.bySemanticsLabel('Next page'), findsOneWidget);
    expect(find.bySemanticsLabel('Fit to width'), findsOneWidget);
  });

  testWidgets('an unsupported locale falls back to English (FR-017)',
      (WidgetTester tester) async {
    await pumpLocalizedPreview(tester, const Locale('fr'));
    expect(find.text('Page 1 of 2'), findsOneWidget);
    // No raw resource keys leak through.
    expect(find.text('previewPageIndicator'), findsNothing);
    expect(find.bySemanticsLabel('previewNextPage'), findsNothing);
  });
}
