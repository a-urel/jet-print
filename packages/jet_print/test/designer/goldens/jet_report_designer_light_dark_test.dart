// Light/dark golden test for the designer shell (US1 / SC-003).
//
// Extends the WYSIWYG golden harness seeded in feature 001
// (jet_print_placeholder_test.dart): it pins the whole shell's appearance in
// both theme variants so a regression that drops theming on any region — or
// hard-codes a color — is caught visually. Regenerate intentional changes with
// `flutter test --update-goldens`.
@Tags(['golden'])
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

void main() {
  // Rulers are pinned by widget tests, not goldens (decision V1); pump them off
  // so the shell golden stays byte-identical to its pre-rulers baseline.
  testWidgets('JetReportDesigner matches its light golden', (
    WidgetTester tester,
  ) async {
    await pumpDesignerWith(tester, rulers: false, grid: false);

    await expectLater(
      find.byType(JetReportDesigner),
      matchesGoldenFile('jet_report_designer_light.png'),
    );
  });

  testWidgets('JetReportDesigner matches its dark golden', (
    WidgetTester tester,
  ) async {
    await pumpDesignerWith(tester,
        themeMode: ThemeMode.dark, rulers: false, grid: false);

    await expectLater(
      find.byType(JetReportDesigner),
      matchesGoldenFile('jet_report_designer_dark.png'),
    );
  });
}
