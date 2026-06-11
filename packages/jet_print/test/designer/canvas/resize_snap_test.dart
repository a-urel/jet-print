// US2 resize + snap-guide widget test (T044 / SC-004 / acceptance US2.1–US2.4):
// dragging a handle resizes with live feedback; a snap guide appears; Alt
// bypasses snapping.
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
  testWidgets('dragging a handle resizes the element and commits',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.tap(_toolFinder(DesignerToolType.shape));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    final JetRect before = _bounds(controller, id);

    await tester.drag(_bottomRightHandle, const Offset(48, 32));
    await tester.pumpAndSettle();

    final JetRect after = _bounds(controller, id);
    expect(after.width, greaterThan(before.width));
    expect(after.height, greaterThan(before.height));
    expect(controller.canUndo, isTrue);
  });

  testWidgets('the overlay renders a snap guide during a resize and clears it',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.setSnapEnabled(true); // snapping is off by default
    await tester.tap(_toolFinder(DesignerToolType.shape));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    expect(_guideBox, findsNothing); // no guide before a resize

    // Drive a snapping resize on the controller; the overlay must render the
    // resulting guide (the handle-drag → resize gesture is covered above).
    controller.beginResize(id, ResizeHandle.right);
    controller.updateResize(const JetOffset(5, 0), threshold: 6);
    await tester.pump();
    expect(controller.activeGuides, isNotEmpty);
    expect(_guideBox, findsWidgets);

    controller.commitResize();
    await tester.pump();
    expect(_guideBox, findsNothing); // guide cleared on commit
  });

  testWidgets(
      'Alt bypasses snapping for the drag without flipping toggles '
      '(C4.5)', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.setSnapEnabled(true); // snapping is off by default
    await tester.tap(_toolFinder(DesignerToolType.shape));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;
    // Both tools are on; the bypass must suspend snapping for THIS drag only,
    // leaving the persistent toggle state untouched (FR-013).
    expect(controller.snapEnabled, isTrue);
    expect(controller.gridEnabled, isTrue);

    controller.beginResize(id, ResizeHandle.right);
    controller.updateResize(const JetOffset(5, 0),
        threshold: 6, bypassSnap: true);
    await tester.pump();
    expect(controller.activeGuides, isEmpty);
    expect(_guideBox, findsNothing);
    // Toggle state is unchanged — the bypass is a transient modifier, not a flip.
    expect(controller.snapEnabled, isTrue);
    expect(controller.gridEnabled, isTrue);
    controller.cancelResize();
  });
}
