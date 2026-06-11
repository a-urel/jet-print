// Designer top bar test.
//
// The top bar was upgraded from a title + three action buttons into a grouped
// command bar in the style of desktop report designers (DevExpress / Telerik /
// Stimulsoft): a document title, then right-clustered groups separated by
// dividers — history (undo/redo), zoom (out / level / in), view toggles
// (grid/ruler/snap) — and the primary Preview / Save / Export actions. The zoom
// control and view toggles are genuinely interactive (local-only this
// iteration); the primary actions remain non-functional placeholders.
//
// Drives the public `JetReportDesigner` and never reaches into `src/`.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

void main() {
  group('designer top bar', () {
    testWidgets('keeps the report title and primary actions', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      expect(find.text('Untitled report'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('shows history, zoom and view-toggle command groups', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // History.
      expect(find.byIcon(LucideIcons.undo2), findsOneWidget);
      expect(find.byIcon(LucideIcons.redo2), findsOneWidget);
      // Zoom.
      expect(find.byIcon(LucideIcons.zoomOut), findsOneWidget);
      expect(find.byIcon(LucideIcons.zoomIn), findsOneWidget);
      // View toggles.
      expect(find.byIcon(LucideIcons.grid2x2), findsOneWidget);
      expect(find.byIcon(LucideIcons.ruler), findsOneWidget);
    });

    testWidgets('the zoom control is interactive', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // The canvas drives the zoom % (it fits the page to width on load).
      final Finder zoomLevel = find
          .byKey(const ValueKey<String>('jet_print.designer.action.zoomLevel'));
      int pct() =>
          int.parse(tester.widget<Text>(zoomLevel).data!.replaceAll('%', ''));

      final int initial = pct();
      await tester.tap(find.byIcon(LucideIcons.zoomIn));
      await tester.pumpAndSettle();
      expect(pct(), greaterThan(initial));

      final int zoomedIn = pct();
      await tester.tap(find.byIcon(LucideIcons.zoomOut));
      await tester.pumpAndSettle();
      expect(pct(), lessThan(zoomedIn));
    });

    testWidgets('tool buttons are left-aligned; primary actions stay right', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      final double mid = kDesktopSize.width / 2;
      // The tool groups sit on the left, next to the title…
      expect(
          tester.getCenter(find.byIcon(LucideIcons.undo2)).dx, lessThan(mid));
      expect(
        tester.getCenter(find.byIcon(LucideIcons.grid2x2)).dx,
        lessThan(mid),
      );
      // …while the primary actions remain on the right edge.
      expect(tester.getCenter(find.text('Export')).dx, greaterThan(mid));
    });

    testWidgets('adjacent tool buttons are separated by ~4px', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      Rect buttonOf(IconData icon) => tester.getRect(
            find.ancestor(
              of: find.byIcon(icon),
              matching: find.byType(ShadIconButton),
            ),
          );
      final double gap =
          buttonOf(LucideIcons.redo2).left - buttonOf(LucideIcons.undo2).right;
      expect(gap, closeTo(4, 1.5));
    });

    testWidgets('does not overflow at narrow widths in any locale', (
      WidgetTester tester,
    ) async {
      for (final Locale locale in const <Locale>[
        Locale('en'),
        Locale('tr'),
        Locale('de'),
      ]) {
        await pumpDesigner(
          tester,
          size: const Size(700, 760),
          locale: locale,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'top bar overflowed at 700px in ${locale.languageCode}',
        );
      }
    });

    testWidgets('does not overflow at a very narrow width (scrolls)', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        size: const Size(440, 760),
        locale: const Locale('tr'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapses action labels to icons and hides title when narrow',
        (WidgetTester tester) async {
      await pumpDesigner(tester, size: const Size(700, 760));

      // Labels disappear, but the action glyphs (and tooltips) remain.
      expect(find.text('Preview'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Export'), findsNothing);
      expect(find.byIcon(LucideIcons.eye), findsOneWidget);
      expect(find.byIcon(LucideIcons.download), findsOneWidget);
      // The title yields its space to the tools when compact.
      expect(find.text('Untitled report'), findsNothing);
    });

    // US2 (C3.4): the ruler toggle is wired to the controller exactly like the
    // grid/snap toggles — it flips `rulersEnabled` and its active styling
    // (secondary vs ghost) tracks that flag at every step.
    testWidgets('the ruler toggle drives rulersEnabled and reflects its state',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      final Finder toggle =
          find.byKey(const ValueKey<String>('jet_print.designer.toggle.ruler'));
      ShadButtonVariant variant() =>
          tester.widget<ShadIconButton>(toggle).variant;

      // Default on → active (secondary) styling.
      expect(c.rulersEnabled, isTrue);
      expect(variant(), ShadButtonVariant.secondary);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.rulersEnabled, isFalse);
      expect(variant(), ShadButtonVariant.ghost);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.rulersEnabled, isTrue);
      expect(variant(), ShadButtonVariant.secondary);
    });

    // 015 (C5.1): the grid toggle flips `gridEnabled` (visibility only) and
    // reflects its state, WITHOUT touching `snapEnabled` — the two tools are
    // independent (FR-010).
    testWidgets('the grid toggle drives gridEnabled and leaves snap untouched',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      final Finder toggle =
          find.byKey(const ValueKey<String>('jet_print.designer.toggle.grid'));
      ShadButtonVariant variant() =>
          tester.widget<ShadIconButton>(toggle).variant;

      // Grid is on by default; snap is off by default.
      expect(c.gridEnabled, isTrue);
      expect(c.snapEnabled, isFalse);
      expect(variant(), ShadButtonVariant.secondary);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.gridEnabled, isFalse);
      expect(c.snapEnabled, isFalse, reason: 'grid toggle must not touch snap');
      expect(variant(), ShadButtonVariant.ghost);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.gridEnabled, isTrue);
      expect(c.snapEnabled, isFalse);
      expect(variant(), ShadButtonVariant.secondary);
    });

    // 015 (C5.2): the snap (magnet) toggle flips `snapEnabled` and reflects its
    // state, WITHOUT touching `gridEnabled` (FR-010).
    testWidgets('the snap toggle drives snapEnabled and leaves grid untouched',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      final Finder toggle =
          find.byKey(const ValueKey<String>('jet_print.designer.toggle.snap'));
      ShadButtonVariant variant() =>
          tester.widget<ShadIconButton>(toggle).variant;

      // Snap is off by default → ghost; grid is on.
      expect(c.snapEnabled, isFalse);
      expect(c.gridEnabled, isTrue);
      expect(variant(), ShadButtonVariant.ghost);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.snapEnabled, isTrue);
      expect(c.gridEnabled, isTrue, reason: 'snap toggle must not touch grid');
      expect(variant(), ShadButtonVariant.secondary);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.snapEnabled, isFalse);
      expect(c.gridEnabled, isTrue);
      expect(variant(), ShadButtonVariant.ghost);
    });
  });
}
