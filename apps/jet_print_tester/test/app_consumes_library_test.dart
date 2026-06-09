// Consumption widget test (US2 / FR-002 / FR-005 / FR-022).
//
// Proves the tester app really consumes the library through its public API:
//  * pumping the app's root yields exactly one JetReportDesigner in a ShadApp;
//  * the app owns a controller and wires the Save/Open persistence callbacks;
//  * the edit → save → reopen path the app implements (a JetReportFormat round
//    trip) preserves an edit — exercised directly through the public API, since
//    the native file picker cannot run in a widget test.
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

  testWidgets(
    'the app owns a controller and wires the Save/Open callbacks (FR-022)',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintTesterApp());

      final JetReportDesigner designer =
          tester.widget<JetReportDesigner>(find.byType(JetReportDesigner));
      expect(designer.controller, isNotNull,
          reason: 'the app owns the controller');
      expect(designer.onSaveRequested, isNotNull,
          reason: 'Save is wired to a host persistence callback');
      expect(designer.onOpenRequested, isNotNull,
          reason: 'Open is wired to a host persistence callback');
    },
  );

  test(
    'edit → save → reopen through the public API preserves the edit (SC-002)',
    () {
      // Edit: create a text element and rename it.
      final JetReportDesignerController editor = JetReportDesignerController();
      addTearDown(editor.dispose);
      editor.createElement(DesignerToolType.text,
          bandIndex: 1, at: const JetOffset(20, 20));
      final String id = editor.selection.singleOrNull!;
      editor.setText(id, 'Invoice total');

      // Save: the exact call the app's onSaveRequested makes.
      final String saved = JetReportFormat.encodeJson(editor.template);

      // Reopen: the exact call the app's onOpenRequested makes.
      final JetReportDesignerController reopened = JetReportDesignerController()
        ..open(JetReportFormat.decodeJson(saved));
      addTearDown(reopened.dispose);

      final TextElement restored = reopened.template.bands
          .expand((ReportBand b) => b.elements)
          .firstWhere((ReportElement e) => e.id == id) as TextElement;
      expect(restored.text, 'Invoice total');
    },
  );
}
