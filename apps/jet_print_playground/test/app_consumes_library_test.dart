// Consumption widget test (US2 / FR-002 / FR-005 / FR-022).
//
// Proves the playground app really consumes the library through its public API:
//  * pumping the app's root yields exactly one JetReportDesigner in a ShadApp;
//  * the app owns a controller and wires the Save/Open persistence callbacks;
//  * the edit → save → reopen path the app implements (a JetReportFormat round
//    trip) preserves an edit — exercised directly through the public API, since
//    the native file picker cannot run in a widget test.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/invoice_sample.dart';
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
    'the shell shows seven live designer tabs and no placeholder',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintPlaygroundApp());

      // All seven tab labels are present in the strip. The app launches in its
      // first supported locale (English), so the labels resolve through
      // AppLocalizations to their English values. Scope the match to the tab
      // strip (ShadTab) so e.g. "Invoice" matches the tab — not the identical
      // report name the designer's top bar also shows.
      for (final String label in const <String>[
        'Empty',
        'Invoice',
        'Label',
        'Barcode',
        'Packing slip',
        'Payroll',
        'List',
        'Menu',
      ]) {
        expect(find.widgetWithText(ShadTab<String>, label), findsOneWidget,
            reason: '"$label" tab label');
      }
      // The Invoice tab is selected on launch, so its designer is on-screen; the
      // other designers are kept alive Offstage and skipped by the default
      // finder.
      expect(find.byType(JetReportDesigner), findsOneWidget);
      // Every demo tab is now a live designer — the old "coming soon"
      // placeholder card is gone entirely.
      expect(find.text('Coming soon', skipOffstage: false), findsNothing);
    },
  );

  testWidgets(
    'the Empty tab activates a blank designer over the same invoice data',
    (WidgetTester tester) async {
      // Wide enough that the full sample tab strip fits without horizontal
      // overflow: the rightmost 'Empty' tab would otherwise scroll under the
      // pinned theme/locale toggle cluster (the strip and the cluster share a
      // Stack), leaving it obscured and untappable.
      await tester.binding.setSurfaceSize(const Size(1400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // Switching to the Empty tab puts the invoice designer offstage — the
      // reverse of the launch state — which must not crash on layout (both
      // designer tabs are kept alive with unbounded height when unselected).
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Empty'));
      await tester.pumpAndSettle();

      // The now-selected designer is the blank seed (no elements), wired to the
      // SAME invoice schema as the Fatura tab.
      final JetReportDesigner designer =
          tester.widget<JetReportDesigner>(find.byType(JetReportDesigner));
      expect(designer.dataSchema, same(invoiceSchema),
          reason: 'the empty tab shares the invoice data source');
      final ReportDefinition definition = designer.controller!.definition;
      expect(definition.name, 'Empty');
      final Iterable<ReportElement> elements = definition.body.root.children
          .whereType<BandNode>()
          .expand((BandNode n) => n.band.elements);
      expect(elements, isEmpty, reason: 'the seed design is blank');
    },
  );

  testWidgets(
    'at phone width every demo tab is reachable, not hidden by the toggles',
    (WidgetTester tester) async {
      // A phone-portrait surface (below the 600px shell breakpoint).
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'the shell lays out cleanly at phone width');

      // Every demo tab still exists in the strip (kept alive Offstage where
      // unselected; scrolled-but-present where the strip overflows).
      for (final String label in const <String>[
        'Invoice',
        'Label',
        'Barcode',
        'Packing slip',
        'Payroll',
        'List',
        'Menu',
        'Empty',
      ]) {
        expect(find.widgetWithText(ShadTab<String>, label), findsOneWidget,
            reason: '"$label" tab');
      }

      // The theme/locale toggles sit ABOVE the demo strip on a phone — not
      // overlaid on its right end where they hid the rightmost demos (the
      // iOS-Simulator smoke bug). Prove it geometrically: the toggle row's
      // bottom is at or above the (always-visible, leftmost) Invoice tab's top,
      // so the cluster cannot occlude any tab.
      final Rect toggle =
          tester.getRect(find.widgetWithText(ShadButton, 'Dark'));
      final Rect invoiceTab =
          tester.getRect(find.widgetWithText(ShadTab<String>, 'Invoice'));
      expect(toggle.bottom, lessThanOrEqualTo(invoiceTab.top + 1.0),
          reason:
              'the toggles are stacked above the strip, not overlaid on it');
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
          bandId: 'detail', at: const JetOffset(20, 20));
      final String id = editor.selection.singleOrNull!;
      editor.setText(id, 'Invoice total');

      // Save: the exact call the app's onSaveRequested makes.
      final String saved =
          JetReportFormat.encodeDefinitionJson(editor.definition);

      // Reopen: the exact call the app's onOpenRequested makes.
      final JetReportDesignerController reopened = JetReportDesignerController()
        ..open(JetReportFormat.decodeDefinitionJson(saved));
      addTearDown(reopened.dispose);

      final TextElement restored = reopened.definition.body.root.children
          .whereType<BandNode>()
          .expand((BandNode n) => n.band.elements)
          .firstWhere((ReportElement e) => e.id == id) as TextElement;
      expect(restored.text, 'Invoice total');
    },
  );
}
