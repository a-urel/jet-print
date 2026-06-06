// Design-surface test.
//
// The center surface shows a fixed-aspect, paper-like page with an empty-state
// hint. At very small window sizes the hint must not overflow the page — the
// page content lives in a scrollable area instead.
//
// Drives the public `JetReportDesigner` and never reaches into `src/`.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/designer_harness.dart';

void main() {
  group('design surface', () {
    testWidgets('does not overflow at a tiny window size', (
      WidgetTester tester,
    ) async {
      for (final Locale locale in const <Locale>[Locale('en'), Locale('tr')]) {
        await pumpDesigner(
          tester,
          size: const Size(320, 480),
          locale: locale,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'surface overflowed at 320x480 in ${locale.languageCode}',
        );
      }
    });

    testWidgets('still shows the empty-state hint', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      expect(
        find.text('Drag elements from the toolbox onto the page to begin.'),
        findsOneWidget,
      );
    });
  });
}
