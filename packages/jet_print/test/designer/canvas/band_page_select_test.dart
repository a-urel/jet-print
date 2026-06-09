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
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    final PageFormat page = controller.template.page;
    final JetEdgeInsets m = page.margins;
    // Band 1 (detail) center: below band 0 (page header), centered horizontally.
    final double h0 = controller.template.bands[0].height;
    final double h1 = controller.template.bands[1].height;
    final double cx = m.left + (page.width - m.left - m.right) / 2;
    final double cy = m.top + h0 + h1 / 2;

    final Offset Function(double, double) at = pageMapper(tester, controller);
    await tester.tapAt(at(cx, cy));
    await tester.pumpAndSettle();

    expect(controller.selection.bandIndex, 1);
  });

  testWidgets('clicking the paper off any band selects the report',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    // The top-left margin corner: inside the paper, inside no band.
    final Offset Function(double, double) at = pageMapper(tester, controller);
    await tester.tapAt(at(2, 2));
    await tester.pumpAndSettle();

    expect(controller.selection.isReport, isTrue);
    expect(controller.selection.bandIndex, isNull);
  });

  testWidgets('clicking off the paper clears the selection',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.selectReport();
    await tester.pump();
    expect(controller.selection.isEmpty, isFalse);

    // The muted canvas margin left of the page (off the paper).
    final Offset canvasTopLeft = tester.getTopLeft(find.byKey(kDesignCanvasKey));
    await tester.tapAt(canvasTopLeft + const Offset(6, 120));
    await tester.pumpAndSettle();

    expect(controller.selection.isEmpty, isTrue);
  });

  testWidgets('clicking an element still selects the element',
      (WidgetTester tester) async {
    final JetReportDesignerController controller = await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(30, 20));
    final String id = controller.selection.singleOrNull!;
    controller.selectReport(); // move selection away first
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(_elementFinder(id)));
    await tester.pumpAndSettle();

    expect(controller.selection.singleOrNull, id);
  });
}
