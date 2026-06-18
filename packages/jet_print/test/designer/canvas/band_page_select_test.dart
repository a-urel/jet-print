// The report (page) and individual bands are selectable by clicking the canvas:
// clicking a band's empty area selects that band, clicking the paper off any
// band selects the report, and clicking off the paper clears. Clicking an
// element still selects the element. Drives the public designer only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

// Maps a page point (points) to a global screen offset, accounting for the
// page's position and the live zoom.
Offset Function(double, double) pageMapper(
    WidgetTester tester, JetReportDesignerController controller) {
  final Offset pageTopLeft = tester.getTopLeft(find.byKey(kDesignPageKey));
  final double s = controller.viewScale;
  return (double px, double py) => pageTopLeft + Offset(px * s, py * s);
}

void main() {
  testWidgets('clicking a band\'s empty area selects that band',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    final PageFormat page = controller.definition.page;
    final JetEdgeInsets m = page.margins;
    // The `detail` band center: below the page header, centered horizontally.
    final double h0 = controller.definition.furniture.pageHeader!.height;
    final double h1 = controller.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .height;
    final double cx = m.left + (page.width - m.left - m.right) / 2;
    final double cy = m.top + h0 + h1 / 2;

    final Offset Function(double, double) at = pageMapper(tester, controller);
    await tester.tapAt(at(cx, cy));
    await tester.pumpAndSettle();

    expect(controller.selection.bandId, 'detail');
  });

  testWidgets('clicking the paper off any band selects the report',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    // The top-left margin corner: inside the paper, inside no band.
    final Offset Function(double, double) at = pageMapper(tester, controller);
    await tester.tapAt(at(2, 2));
    await tester.pumpAndSettle();

    expect(controller.selection.isReport, isTrue);
    expect(controller.selection.bandId, isNull);
  });

  testWidgets('clicking off the paper clears the selection',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.selectReport();
    await tester.pump();
    expect(controller.selection.isEmpty, isFalse);

    // The muted canvas margin just left of the page (off the paper). Anchored to
    // the page edge so it stays in the margin regardless of the ruler inset.
    final Offset pageTopLeft = tester.getTopLeft(find.byKey(kDesignPageKey));
    await tester.tapAt(Offset(pageTopLeft.dx - 8, pageTopLeft.dy + 120));
    await tester.pumpAndSettle();

    expect(controller.selection.isEmpty, isTrue);
  });

  testWidgets('tapping the left-margin gutter beside a band selects that band',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    final PageFormat page = controller.definition.page;
    final double h0 = controller.definition.furniture.pageHeader!.height;
    final double h1 = controller.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .height;
    // Empty paper in the left-margin gutter (x just inside the sheet, left of
    // the content rect) at the detail band's vertical middle: the band strip
    // between its top and bottom separators, where no element sits. The whole
    // strip — full page width — must select the band, not the report.
    final double cy = page.margins.top + h0 + h1 / 2;

    controller.selectReport(); // move selection off the detail band first
    await tester.pumpAndSettle();
    expect(controller.selection.bandId, isNull);

    final Offset Function(double, double) at = pageMapper(tester, controller);
    await tester.tapAt(at(2, cy));
    await tester.pumpAndSettle();

    expect(controller.selection.bandId, 'detail');
  });

  testWidgets("tapping a band's tag selects that band",
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.selectReport(); // move selection off the detail band first
    await tester.pumpAndSettle();
    expect(controller.selection.bandId, isNull);

    // The tag sits in the gutter at the band's top — within the band's strip.
    // It is IgnorePointer'd (the canvas owns selection), so the tap deliberately
    // falls through to the strip beneath it; warnIfMissed would flag that.
    await tester.tap(
      find.byKey(const ValueKey<String>('jet_print.designer.bandBadge.detail')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(controller.selection.bandId, 'detail');
  });

  testWidgets('clicking an element still selects the element',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(30, 20));
    final String id = controller.selection.singleOrNull!;
    controller.selectReport(); // move selection away first
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(_elementFinder(id)));
    await tester.pumpAndSettle();

    expect(controller.selection.singleOrNull, id);
  });
}
