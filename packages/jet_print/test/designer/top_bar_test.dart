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

      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.zoomIn));
      await tester.pumpAndSettle();
      expect(find.text('110%'), findsOneWidget);
      expect(find.text('100%'), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.zoomOut));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
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
  });
}
