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
import 'package:jet_print_playground/demo_nav_list.dart';
import 'package:jet_print_playground/main.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  // A nav entry is a ShadButton (label as its text) inside the shared
  // DemoNavList. Scoping to DemoNavList avoids matching the identical report
  // name the designer's own top bar shows. On a wide surface only the sidebar
  // copy is onstage (the drawer copy is offstage), so a default find matches
  // exactly one; on a phone the only copy is the drawer's, onstage once opened.
  Finder navItem(String label) => find.descendant(
        of: find.byType(DemoNavList),
        matching: find.widgetWithText(ShadButton, label),
      );
  testWidgets(
    'root widget renders a JetReportWorkspace wrapping the designer',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintPlaygroundApp());

      expect(find.byType(ShadApp), findsOneWidget);
      expect(
          find.byType(JetReportWorkspace, skipOffstage: false), findsWidgets);
      // All demo designers are mounted in the IndexedStack; non-selected ones are
      // Offstage (via IndexedStack/Visibility.maintain) so we skip that filter.
      expect(find.byType(JetReportDesigner, skipOffstage: false), findsWidgets);
    },
  );

  testWidgets(
    'the shell shows eleven live designer tabs and no placeholder',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintPlaygroundApp());

      // All eleven nav entries are present in the DemoNavList. The app launches
      // in its first supported locale (English), so the labels resolve through
      // AppLocalizations to their English values. Scope the match to the
      // DemoNavList via the navItem helper so e.g. "Invoice" matches the nav
      // entry — not the identical report name the designer's top bar also shows.
      for (final String label in const <String>[
        'Empty',
        'Invoice',
        'Label',
        'Barcode',
        'Symbologies',
        'Packing slip',
        'Payroll',
        'List',
        'Ledger',
        'Menu',
        'Custom',
      ]) {
        expect(navItem(label), findsOneWidget, reason: '"$label" nav entry');
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
      // Wide enough that the sidebar is visible and all nav entries are
      // reachable without opening a drawer.
      await tester.binding.setSurfaceSize(const Size(1850, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // Switching to the Empty tab changes the IndexedStack index — all designers
      // stay mounted; only the shown one changes.
      await tester.tap(navItem('Empty'));
      await tester.pumpAndSettle();

      // The now-shown designer (the blank seed) is the only onstage one — the
      // others are hidden via IndexedStack/Visibility.maintain/Offstage.
      final JetReportDesigner designer =
          tester.widget<JetReportDesigner>(find.byType(JetReportDesigner));
      expect(designer.dataSchema, isNull,
          reason: 'the empty tab starts with no data source attached');
      expect(designer.onSelectDataSchema, isNotNull,
          reason: 'the empty tab wires the Select data source callback');
      final ReportDefinition definition = designer.controller!.definition;
      expect(definition.name, 'Empty');
      final Iterable<ReportElement> elements = definition.body.root.children
          .whereType<BandNode>()
          .expand((BandNode n) => n.band.elements);
      expect(elements, isEmpty, reason: 'the seed design is blank');
    },
  );

  testWidgets(
    'at phone width the hamburger drawer reaches every demo',
    (WidgetTester tester) async {
      // A phone-portrait surface (below the 600px shell breakpoint).
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'the shell lays out cleanly at phone width');

      // The nav lives in a closed drawer — no entry is onstage yet.
      expect(navItem('Invoice'), findsNothing,
          reason: 'nav is hidden until the hamburger is tapped');

      // Open the drawer via the hamburger.
      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pumpAndSettle();

      // Every demo entry is now present and reachable in the open drawer.
      for (final String label in const <String>[
        'Invoice',
        'Label',
        'Barcode',
        'Symbologies',
        'Packing slip',
        'Payroll',
        'List',
        'Ledger',
        'Menu',
        'Custom',
        'Empty',
      ]) {
        expect(navItem(label), findsOneWidget, reason: '"$label" nav entry');
      }

      // Selecting an entry closes the drawer (and switches the demo).
      await tester.tap(navItem('Menu'));
      await tester.pumpAndSettle();
      expect(navItem('Menu'), findsNothing,
          reason: 'the drawer closes after a selection');
    },
  );

  testWidgets(
    'only the Empty demo wires the Save/Open callbacks (FR-022)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1850, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // The launch (Invoice) tab is a read-only sample: Save/Open are NOT wired.
      JetReportWorkspace onstage() =>
          tester.widget<JetReportWorkspace>(find.byType(JetReportWorkspace));
      expect(onstage().controller, isNotNull,
          reason: 'the app owns the controller on every tab');
      expect(onstage().onSaveRequested, isNull);
      expect(onstage().onOpenRequested, isNull);

      // The Empty tab wires the host persistence seam.
      await tester.tap(navItem('Empty'));
      await tester.pumpAndSettle();
      expect(onstage().onSaveRequested, isNotNull,
          reason: 'Save is wired on the Empty tab');
      expect(onstage().onOpenRequested, isNotNull,
          reason: 'Open is wired on the Empty tab');
    },
  );

  testWidgets(
    'Open/Save show only on the Empty demo (gated host file I/O)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1850, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // Launch tab is Invoice — a sample demo: Open/Save are not offered.
      // (find skips Offstage by default, so only the onstage tab counts.)
      expect(find.text('Open'), findsNothing);
      expect(find.text('Save'), findsNothing);

      // The Empty tab wires the host persistence seam, so both appear.
      await tester.tap(navItem('Empty'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    },
  );

  testWidgets(
    'a designer survives a tab switch as the SAME State (no remount, edits kept)',
    (WidgetTester tester) async {
      // Wide enough for the sidebar to be on-screen so both 'Invoice' and
      // 'Empty' taps actually hit their targets.
      await tester.binding.setSurfaceSize(const Size(1850, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // All demo designers stay mounted at once (IndexedStack keep-alive).
      expect(find.byType(JetReportDesigner, skipOffstage: false), findsWidgets);

      // The onstage (selected) designer's State on the initial Invoice tab.
      final State<StatefulWidget> before =
          tester.state(find.byType(JetReportDesigner));

      // Switch away and back.
      await tester.tap(navItem('Empty'));
      await tester.pumpAndSettle();
      await tester.tap(navItem('Invoice'));
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

  testWidgets(
    'a designer survives the wide<->narrow layout swap (no remount)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1850, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // Capture the onstage designer's State at wide layout.
      final State<StatefulWidget> before =
          tester.state(find.byType(JetReportDesigner));

      // Shrink to phone width — crosses the 600dp breakpoint, toggling the
      // sidebar out and the hamburger drawer in. The _bodyKey GlobalKey must
      // migrate the IndexedStack element intact so no designer remounts.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();

      final State<StatefulWidget> after =
          tester.state(find.byType(JetReportDesigner));
      expect(identical(before, after), isTrue,
          reason:
              'the designer must survive the wide↔narrow layout swap (the _bodyKey GlobalKey)');
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
