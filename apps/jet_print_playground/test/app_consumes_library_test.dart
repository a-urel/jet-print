// Consumption widget test (US2 / FR-002 / FR-005 / FR-022).
//
// Proves the playground app really consumes the library through its public API:
//  * pumping the app's root yields exactly one JetReportDesigner in a ShadApp;
//  * the app owns a controller and wires the Save/Open persistence callbacks;
//  * the edit → save → reopen path the app implements (a JetReportFormat round
//    trip) preserves an edit — exercised directly through the public API, since
//    the native file picker cannot run in a widget test.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/main.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'root widget renders a JetReportWorkspace wrapping the designer',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintPlaygroundApp());

      expect(find.byType(ShadApp), findsOneWidget);
      expect(find.byType(JetReportWorkspace), findsOneWidget);
      // The workspace opens in designer mode, so its designer is on-screen.
      expect(find.byType(JetReportDesigner), findsOneWidget);
    },
  );

  testWidgets(
    'the app owns a controller and wires the Save/Open callbacks (FR-022)',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintPlaygroundApp());

      final JetReportWorkspace workspace =
          tester.widget<JetReportWorkspace>(find.byType(JetReportWorkspace));
      expect(workspace.controller, isNotNull,
          reason: 'the app owns the controller');
      expect(workspace.onSaveRequested, isNotNull,
          reason: 'Save is wired to a host persistence callback');
      expect(workspace.onOpenRequested, isNotNull,
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
