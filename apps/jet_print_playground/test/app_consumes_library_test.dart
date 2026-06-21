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
      expect(find.byType(JetReportWorkspace, skipOffstage: false), findsWidgets);
      // All demo designers are mounted in the IndexedStack; non-selected ones are
      // Offstage (via IndexedStack/Visibility.maintain) so we skip that filter.
      expect(find.byType(JetReportDesigner, skipOffstage: false), findsWidgets);
    },
  );

  testWidgets(
    'the shell shows eight live designer tabs and no placeholder',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintPlaygroundApp());

      // All eight tab labels are present in the strip. The app launches in its
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
      // All demo designers are mounted in the IndexedStack; non-selected are
      // Offstage (Visibility.maintain), so pass skipOffstage:false.
      expect(find.byType(JetReportDesigner, skipOffstage: false), findsWidgets);
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

      // Switching to the Empty tab changes the IndexedStack index — all designers
      // stay mounted; only the shown one changes.
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Empty'));
      await tester.pumpAndSettle();

      // The now-shown designer (the blank seed) is the only onstage one — the
      // others are hidden via IndexedStack/Visibility.maintain/Offstage.
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

      // The selected (onstage) workspace — others are Offstage in the IndexedStack.
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

  testWidgets(
    'a designer survives a tab switch as the SAME State (no remount, edits kept)',
    (WidgetTester tester) async {
      // Wide enough for the full tab strip to be on-screen so both 'Invoice'
      // and 'Empty' taps actually hit their targets (same reason as the
      // 'Empty tab activates a blank designer' test above).
      await tester.binding.setSurfaceSize(const Size(1400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // All demo designers stay mounted at once (IndexedStack keep-alive).
      expect(find.byType(JetReportDesigner, skipOffstage: false), findsWidgets);

      // The onstage (selected) designer's State on the initial Invoice tab.
      final State<StatefulWidget> before =
          tester.state(find.byType(JetReportDesigner));

      // Switch away and back.
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Empty'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Invoice'));
      await tester.pumpAndSettle();

      // Same State instance ⇒ the subtree was never torn down, so its
      // controller and any in-progress edits survive. A remount (the bug this
      // guards) yields a different State and fails here.
      final State<StatefulWidget> after =
          tester.state(find.byType(JetReportDesigner));
      expect(identical(before, after), isTrue,
          reason: 'designer must not remount on a tab switch');
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
