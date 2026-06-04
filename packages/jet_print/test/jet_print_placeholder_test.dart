// Placeholder widget + golden test (FR-004 / Constitution Principle IV).
//
// Pumps the placeholder standalone, asserts it renders, and pins its appearance
// with a golden image. This seeds the WYSIWYG harness now so that, when real
// rendering arrives, fidelity is already enforced day one.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('JetPrintPlaceholder renders and matches its golden', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ShadApp(home: Center(child: JetPrintPlaceholder())),
    );

    expect(find.byType(JetPrintPlaceholder), findsOneWidget);

    await expectLater(
      find.byType(JetPrintPlaceholder),
      matchesGoldenFile('goldens/jet_print_placeholder.png'),
    );
  });
}
