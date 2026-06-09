// Designer seam test (SC-004).
//
// Unlike the domain/rendering seams, the designer seam's output (the placeholder
// widget) is part of the public surface, so this test consumes it through the
// public entry point — proving the designer seam is exercisable independently of
// the playground app.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'JetPrintPlaceholder builds standalone inside a ShadApp shell',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ShadApp(home: JetPrintPlaceholder()));

      expect(find.byType(JetPrintPlaceholder), findsOneWidget);
      expect(find.text('jet_print'), findsOneWidget);
    },
  );
}
