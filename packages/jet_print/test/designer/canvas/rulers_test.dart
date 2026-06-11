// Ruler presence / visibility widget tests (spec 014, C3 / FR-001, FR-006,
// FR-007, FR-013, FR-017). Drives the public `JetReportDesigner` only and locates
// the rulers by their stable widget keys (never reaching into `src/`), exactly as
// the other canvas widget tests locate the page and scrollbars.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/designer_harness.dart';

// Stable keys mirrored from `canvas/ruler_overlay.dart` (the test seam).
const Key _kHorizontalRuler =
    ValueKey<String>('jet_print.designer.ruler.horizontal');
const Key _kVerticalRuler =
    ValueKey<String>('jet_print.designer.ruler.vertical');
const Key _kRulerCorner = ValueKey<String>('jet_print.designer.ruler.corner');

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
    testWidgets('a horizontal ruler is present at the top and a vertical at left',
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
        find.descendant(of: find.byKey(_kRulerCorner), matching: find.byType(Text)),
        findsNothing,
        reason: 'the corner is blank — no label, no measurement',
      );
    });
  });
}
