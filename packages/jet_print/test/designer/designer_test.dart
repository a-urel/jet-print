// Designer seam test (SC-004).
//
// Proves the designer seam is exercisable independently of the playground app:
// it consumes the public report-designer shell through the single public entry
// point and builds it standalone inside a ShadApp shell.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'JetReportDesigner builds standalone inside a ShadApp shell',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ShadApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            JetPrintLocalizations.delegate,
          ],
          supportedLocales: JetPrintLocalizations.supportedLocales,
          home: const JetReportDesigner(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(JetReportDesigner), findsOneWidget);
    },
  );
}
