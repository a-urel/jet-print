// Light/dark golden test for the designer shell (US1 / SC-003).
//
// Extends the WYSIWYG golden harness seeded in feature 001
// (jet_print_placeholder_test.dart): it pins the whole shell's appearance in
// both theme variants so a regression that drops theming on any region — or
// hard-codes a color — is caught visually. Regenerate intentional changes with
// `flutter test --update-goldens`.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

void main() {
  testWidgets('JetReportDesigner matches its light golden', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester);

    await expectLater(
      find.byType(JetReportDesigner),
      matchesGoldenFile('jet_report_designer_light.png'),
    );
  });

  testWidgets('JetReportDesigner matches its dark golden', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, themeMode: ThemeMode.dark);

    await expectLater(
      find.byType(JetReportDesigner),
      matchesGoldenFile('jet_report_designer_dark.png'),
    );
  });
}
