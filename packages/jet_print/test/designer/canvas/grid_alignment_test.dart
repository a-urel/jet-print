// Grid alignment under zoom & pan (spec 015, US3 / contract C3 / FR-005,
// FR-006, SC-002, SC-006). Mirrors ruler_alignment_test.dart / zoom_pan_test.dart
// but for the on-page grid: because the grid is a Positioned.fill child of the
// page Stack, it inherits the page's scale and scroll transform, so a page point
// maps to the same grid pixel at every zoom/scroll — verified here by asserting
// the grid layer stays registered to (exactly overlays) the page surface. The
// per-line thinning/hiding at low zoom is pinned at the unit level by
// grid_geometry_test (C1.2/C1.3); this file pins the registration invariant.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

const Key _kGrid = ValueKey<String>('jet_print.designer.grid');

/// The grid layer's painted rect (the CustomPaint render box under the keyed
/// Positioned — the Positioned itself carries no render object).
Rect _gridRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(
              of: find.byKey(_kGrid), matching: find.byType(CustomPaint))
          .first,
    );

Rect _pageRect(WidgetTester tester) =>
    tester.getRect(find.byKey(kDesignPageKey));

ScrollableState _scrollable(WidgetTester tester, Axis axis) => tester
    .stateList<ScrollableState>(
      find.descendant(
        of: find.byKey(kDesignCanvasKey),
        matching: find.byType(Scrollable),
      ),
    )
    .firstWhere((ScrollableState s) => s.position.axis == axis);

/// The grid must exactly overlay the page surface (it is registered to the page,
/// scaling and scrolling with it).
void _expectRegistered(WidgetTester tester) {
  final Rect grid = _gridRect(tester);
  final Rect page = _pageRect(tester);
  expect(grid.left, closeTo(page.left, 1.0));
  expect(grid.top, closeTo(page.top, 1.0));
  expect(grid.width, closeTo(page.width, 1.0));
  expect(grid.height, closeTo(page.height, 1.0));
}

void main() {
  testWidgets('C3.1 grid stays registered to the page at min/100%/max zoom',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);

    for (final double scale in <double>[0.25, 1.0, 4.0]) {
      c.setViewScale(scale);
      await tester.pumpAndSettle();
      expect(find.byKey(_kGrid), findsOneWidget);
      _expectRegistered(tester);
    }
    // The grid scales with the page: it is wider at max zoom than at min zoom.
    c.setViewScale(0.25);
    await tester.pumpAndSettle();
    final double small = _gridRect(tester).width;
    c.setViewScale(4.0);
    await tester.pumpAndSettle();
    expect(_gridRect(tester).width, greaterThan(small));
  });

  testWidgets('C3.2 the grid scrolls with the page (stays registered)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setViewScale(4.0); // overflow the viewport so it can scroll
    await tester.pumpAndSettle();
    _expectRegistered(tester);

    final ScrollableState v = _scrollable(tester, Axis.vertical);
    expect(v.position.maxScrollExtent, greaterThan(0));
    v.position.jumpTo(200);
    await tester.pumpAndSettle();

    // After scrolling, the grid and page both shifted by the same amount — the
    // grid is still locked to the page.
    _expectRegistered(tester);
  });

  testWidgets('C3.3 zoomed far out the grid stays page-bounded (not a fill)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setViewScale(0.25); // the lowest the UI allows
    await tester.pumpAndSettle();

    // The grid is still drawn and clipped to the page (it never spills into a
    // solid fill); at this zoom the pure helper has coarsened the lines, which
    // grid_geometry_test pins at the unit level (C1.2/C1.3).
    expect(find.byKey(_kGrid), findsOneWidget);
    _expectRegistered(tester);
  });
}
