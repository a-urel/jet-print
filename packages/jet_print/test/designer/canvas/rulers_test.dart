// Ruler presence / visibility widget tests (spec 014, C3 / FR-001, FR-006,
// FR-007, FR-013, FR-017). Drives the public `JetReportDesigner` only and locates
// the rulers by their stable widget keys (never reaching into `src/`), exactly as
// the other canvas widget tests locate the page and scrollbars.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

// Stable keys mirrored from `canvas/ruler_overlay.dart` (the test seam).
const Key _kHorizontalRuler =
    ValueKey<String>('jet_print.designer.ruler.horizontal');
const Key _kVerticalRuler =
    ValueKey<String>('jet_print.designer.ruler.vertical');
const Key _kRulerCorner = ValueKey<String>('jet_print.designer.ruler.corner');

/// The live viewport dimension of the canvas's scroll view along [axis]. Grows
/// when the rulers are hidden (the strip space is reclaimed).
double _viewportExtent(WidgetTester tester, Axis axis) => tester
    .stateList<ScrollableState>(
      find.descendant(
        of: find.byKey(kDesignCanvasKey),
        matching: find.byType(Scrollable),
      ),
    )
    .firstWhere((ScrollableState s) => s.position.axis == axis)
    .position
    .viewportDimension;

/// Whether [finder] resolves to a widget showing at least one numeric label.
bool _hasNumberedMarks(WidgetTester tester, Finder ruler) {
  final Iterable<Text> labels = tester.widgetList<Text>(
    find.descendant(of: ruler, matching: find.byType(Text)),
  );
  return labels.any((Text t) {
    final String? data = t.data?.replaceAll(RegExp('[.,  ]'), '');
    return data != null && data.isNotEmpty && int.tryParse(data) != null;
  });
}

void main() {
  group('rulers — US1 presence (C3.1, C3.5)', () {
    testWidgets(
        'a horizontal ruler is present at the top and a vertical at left',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);

      expect(find.byKey(_kHorizontalRuler), findsOneWidget);
      expect(find.byKey(_kVerticalRuler), findsOneWidget);

      // The horizontal ruler hugs the top; the vertical one the left edge.
      final Rect h = tester.getRect(find.byKey(_kHorizontalRuler));
      final Rect v = tester.getRect(find.byKey(_kVerticalRuler));
      final Rect canvas = tester.getRect(find.byKey(kDesignCanvasKey));
      expect(h.top, closeTo(canvas.top, 0.5));
      expect(v.left, closeTo(canvas.left, 0.5));
      // The horizontal ruler is wider than tall; the vertical taller than wide.
      expect(h.width, greaterThan(h.height));
      expect(v.height, greaterThan(v.width));
    });

    testWidgets('both rulers show numbered millimetre marks (C3.1)',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);

      expect(_hasNumberedMarks(tester, find.byKey(_kHorizontalRuler)), isTrue,
          reason: 'the top ruler must show numbered mm marks');
      expect(_hasNumberedMarks(tester, find.byKey(_kVerticalRuler)), isTrue,
          reason: 'the left ruler must show numbered mm marks');
    });

    testWidgets('the top-left corner box renders no measurement (C3.5, FR-013)',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);

      expect(find.byKey(_kRulerCorner), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(_kRulerCorner), matching: find.byType(Text)),
        findsNothing,
        reason: 'the corner is blank — no label, no measurement',
      );
    });
  });

  group('rulers — US2 toggle visibility (C3.2, C3.3)', () {
    testWidgets(
        'hiding rulers removes both strips and the canvas reclaims them',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);

      expect(find.byKey(_kHorizontalRuler), findsOneWidget);
      final double widthOn = _viewportExtent(tester, Axis.horizontal);
      final double heightOn = _viewportExtent(tester, Axis.vertical);

      c.setRulersEnabled(false);
      await tester.pumpAndSettle();

      // Both strips and the corner are gone.
      expect(find.byKey(_kHorizontalRuler), findsNothing);
      expect(find.byKey(_kVerticalRuler), findsNothing);
      expect(find.byKey(_kRulerCorner), findsNothing);
      // The viewport grows by the strip thickness on each axis (space reclaimed).
      expect(
          _viewportExtent(tester, Axis.horizontal) - widthOn, closeTo(20, 1.5),
          reason: 'the left strip space is reclaimed');
      expect(
          _viewportExtent(tester, Axis.vertical) - heightOn, closeTo(20, 1.5),
          reason: 'the top strip space is reclaimed');
    });

    testWidgets('re-enabling restores both rulers aligned to the canvas edges',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.setRulersEnabled(false);
      await tester.pumpAndSettle();
      expect(find.byKey(_kHorizontalRuler), findsNothing);

      c.setRulersEnabled(true);
      await tester.pumpAndSettle();

      expect(find.byKey(_kHorizontalRuler), findsOneWidget);
      expect(find.byKey(_kVerticalRuler), findsOneWidget);
      final Rect canvas = tester.getRect(find.byKey(kDesignCanvasKey));
      expect(tester.getRect(find.byKey(_kHorizontalRuler)).top,
          closeTo(canvas.top, 0.5));
      expect(tester.getRect(find.byKey(_kVerticalRuler)).left,
          closeTo(canvas.left, 0.5));
    });
  });
}
