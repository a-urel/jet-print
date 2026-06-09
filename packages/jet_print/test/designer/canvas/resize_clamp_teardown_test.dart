// Regression: a resize-handle drag that runs past the band/page boundary (so
// the final size is clamped) must still commit cleanly and tear down the live
// resize state — no stuck preview outline, no stuck snap guide.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _toolFinder(DesignerToolType type) =>
    find.byKey(ValueKey<String>('jet_print.designer.tool.${type.name}'));

final Finder _bottomRightHandle =
    find.byKey(const ValueKey<String>('jet_print.designer.handle.bottomRight'));

final Finder _guideBox = find.byWidgetPredicate(
    (Widget w) => w is ColoredBox && w.color == const Color(0xFFEF4444));

JetRect _bounds(JetReportDesignerController c, String id) => c.template.bands
    .expand((ReportBand b) => b.elements)
    .firstWhere((ReportElement e) => e.id == id)
    .bounds;

void main() {
  testWidgets(
      'a resize dragged past the boundary commits clamped and tears down',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.tap(_toolFinder(DesignerToolType.shape));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    final JetRect before = _bounds(controller, id);

    // Multi-step drag of the bottom-right handle far past the band/page edge.
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(_bottomRightHandle));
    for (int i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(120, 120));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // The element grew (and is clamped to its band), and NOTHING is left stuck.
    final JetRect after = _bounds(controller, id);
    expect(after.width, greaterThan(before.width), reason: 'resized wider');
    expect(controller.previewBoundsFor(id), isNull,
        reason: 'no stuck resize preview');
    expect(controller.activeGuides, isEmpty, reason: 'no stuck snap guide');
    expect(_guideBox, findsNothing, reason: 'no red guide painted at rest');
  });
}
