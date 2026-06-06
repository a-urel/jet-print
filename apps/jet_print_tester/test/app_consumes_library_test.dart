// Consumption widget test (US2 / FR-002 / FR-005).
//
// Proves the tester app really consumes the library through its public API and
// that the shadcn theming pipeline is present: pumping the app's root widget
// must yield exactly one JetReportDesigner wrapped in a ShadApp.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_tester/main.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'root widget renders one JetReportDesigner inside a ShadApp',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintTesterApp());

      // The shadcn theming pipeline is present...
      expect(find.byType(ShadApp), findsOneWidget);
      // ...and the library's designer shell is consumed exactly once.
      expect(find.byType(JetReportDesigner), findsOneWidget);
    },
  );
}
