// Region-presence widget test (US1 / FR-001/002/003, SC-004).
//
// Pumps JetReportDesigner at desktop width and proves all four regions render
// simultaneously, the design surface owns the largest horizontal share, and the
// full layout fits the default desktop width with no horizontal overflow.
//
// US3 representative-placeholder-content assertions are appended here (T026).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

void main() {
  group('JetReportDesigner regions (desktop width)', () {
    testWidgets('renders top bar, toolbox, surface and right panel together', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      expect(find.byKey(kTopBarKey), findsOneWidget);
      expect(find.byKey(kToolboxKey), findsOneWidget);
      expect(find.byKey(kSurfaceKey), findsOneWidget);
      expect(find.byKey(kRightPanelKey), findsOneWidget);

      // The English chrome captions are present (sourced from l10n, not hard
      // coded) — top-bar title and the three tab captions. The toolbox is an
      // icon toolbar (names live in tooltips), asserted separately below.
      expect(find.text('Untitled report'), findsOneWidget);
      expect(find.text('Data Source'), findsWidgets);
      expect(find.text('Outline'), findsWidgets);
      expect(find.text('Properties'), findsWidgets);
    });

    testWidgets('the design surface occupies the largest horizontal share', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      final double toolboxWidth = tester.getSize(find.byKey(kToolboxKey)).width;
      final double surfaceWidth = tester.getSize(find.byKey(kSurfaceKey)).width;
      final double rightWidth =
          tester.getSize(find.byKey(kRightPanelKey)).width;

      expect(
        surfaceWidth,
        greaterThan(toolboxWidth),
        reason: 'surface must be wider than the toolbox',
      );
      expect(
        surfaceWidth,
        greaterThan(rightWidth),
        reason: 'surface must be wider than the right panel',
      );
    });

    testWidgets('lays out within the desktop width without horizontal overflow',
        (WidgetTester tester) async {
      await pumpDesigner(tester);

      // A RenderFlex/overflow during layout records an exception the framework
      // surfaces here; a clean layout leaves none (SC-004).
      expect(tester.takeException(), isNull);

      // No region extends past the right edge of the window.
      final double windowRight =
          tester.getBottomRight(find.byKey(kTopBarKey)).dx;
      expect(windowRight, lessThanOrEqualTo(kDesktopSize.width + 0.5));
    });
  });

  group('JetReportDesigner minimum width', () {
    // Mirrors _JetReportDesignerState._minShellWidth.
    const double minShellWidth = 600;

    testWidgets('clamps to a minimum width and scrolls when very narrow', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester, size: const Size(320, 760));

      // No overflow at an extreme width…
      expect(tester.takeException(), isNull);
      // …because the shell is laid out at its minimum width (wider than the
      // viewport, reached by horizontal scrolling) rather than squeezed.
      final double topBarWidth = tester.getSize(find.byKey(kTopBarKey)).width;
      expect(topBarWidth, greaterThan(320));
      expect(topBarWidth, closeTo(minShellWidth, 0.5));
    });

    testWidgets('fills the viewport at or above the minimum width', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      final double topBarWidth = tester.getSize(find.byKey(kTopBarKey)).width;
      expect(topBarWidth, closeTo(kDesktopSize.width, 0.5));
    });
  });

  // --- US3: representative placeholder content (T026) ---
  group('JetReportDesigner placeholder content (US3 / FR-007)', () {
    testWidgets('toolbox offers multiple element entries as icon buttons', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // Toolbar form: icon-only buttons (element names live in tooltips). Assert
      // the toolbox offers several distinct element entries (Label/Text/Table/
      // Image and more).
      final Finder toolboxButtons = find.descendant(
        of: find.byKey(kToolboxKey),
        matching: find.byType(ShadIconButton),
      );
      expect(toolboxButtons, findsAtLeastNWidgets(4));
    });

    testWidgets('design surface shows a bounded empty-page hint, not a void', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // The surface communicates intent rather than reading as a blank gap.
      expect(
        find.text('Drag elements from the toolbox onto the page to begin.'),
        findsOneWidget,
      );
    });
  });

  // --- 003: backward-compat construction + default-template structure (T034). ---
  group('JetReportDesigner 003 contract', () {
    testWidgets('const JetReportDesigner() still constructs and hosts a canvas',
        (WidgetTester tester) async {
      await pumpDesigner(tester); // default designer is `const JetReportDesigner()`
      expect(find.byKey(kSurfaceKey), findsOneWidget);
      expect(find.byKey(kDesignCanvasKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('the no-arg controller seeds the default blank band structure', () {
      final JetReportDesignerController controller =
          JetReportDesignerController();
      expect(
        controller.template.bands.map((ReportBand b) => b.type).toList(),
        <BandType>[BandType.pageHeader, BandType.detail, BandType.pageFooter],
      );
      expect(
        controller.template.bands.every((ReportBand b) => b.elements.isEmpty),
        isTrue,
      );
      controller.dispose();
    });
  });
}
