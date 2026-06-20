// Spec 038: a selected element's selection BOX (outline) must stay inside its
// band during a live move (the chrome tracks the clamped element, no drift), and
// the resize handles must HUG the outline corners/edges everywhere — including
// when the element is flush against a band border, where the small handle squares
// are allowed to overlap the band line by half their size (screen-space overlay,
// like mainstream design tools). See the 2026-06-20 clarification in spec.md.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));
final Finder _topLeftHandle =
    find.byKey(const ValueKey<String>('jet_print.designer.handle.topLeft'));
final Finder _bottomRightHandle =
    find.byKey(const ValueKey<String>('jet_print.designer.handle.bottomRight'));

void main() {
  testWidgets(
      'live move clamped at a band edge keeps the chrome glued to the element',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(60, 40));
    await tester.pumpAndSettle();
    final String id = c.selection.singleOrNull!;

    // Simulate a live move that pushes the element far past the band's RIGHT edge.
    // The model clamps the display position while the raw delta grows — which is
    // the exact scenario that used to cause chrome drift before spec 038.
    c.beginMove();
    // 600 pt rightward: enough to exceed any reasonable band width from x=60.
    c.updateMove(const JetOffset(600, 0));
    await tester.pump();

    // The painted element (drawn from the clamped display layout) and the chrome
    // must coincide: the top-left handle is centered on the clamped element's
    // top-left corner, not on the raw (un-clamped) drag position.
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect tl = tester.getRect(_topLeftHandle);
    expect(tl.center.dx, closeTo(elem.left, 1.0), reason: 'chrome tracks element x');
    expect(tl.center.dy, closeTo(elem.top, 1.0), reason: 'chrome tracks element y');

    c.commitMove();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'a flush top-left element keeps its top-left handle ON the corner '
      '(handles hug the outline, no inward tuck)', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    // Flush at the band's top-left: the element's own rect top/left ARE the
    // band's top/left edge.
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(0, 0));
    await tester.pumpAndSettle();

    final String id = c.selection.singleOrNull!;
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect tl = tester.getRect(_topLeftHandle);
    // The handle is centered ON the corner (overlapping the band edge by half a
    // handle), NOT tucked inward — so it stays visually attached to the outline.
    expect(tl.center.dx, closeTo(elem.left, 1.0),
        reason: 'top-left handle hugs the corner (x)');
    expect(tl.center.dy, closeTo(elem.top, 1.0),
        reason: 'top-left handle hugs the corner (y)');
  });

  testWidgets(
      'a flush bottom-right element keeps its bottom-right handle ON the corner '
      '(handles hug the outline)', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    // A huge offset clamps the element flush into the band's bottom-right corner.
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(1000000, 1000000));
    await tester.pumpAndSettle();

    final String id = c.selection.singleOrNull!;
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect br = tester.getRect(_bottomRightHandle);
    expect(br.center.dx, closeTo(elem.right, 1.0),
        reason: 'bottom-right handle hugs the corner (x)');
    expect(br.center.dy, closeTo(elem.bottom, 1.0),
        reason: 'bottom-right handle hugs the corner (y)');
  });

  testWidgets(
      'during a live resize clamped at a band edge the handle hugs the clamped '
      'corner', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(60, 40));
    await tester.pumpAndSettle();
    final String id = c.selection.singleOrNull!;

    // Drag the bottom-right handle far past the band's bottom-right corner and
    // HOLD (no release). The element's size clamps to the band; the handle must
    // ride that clamped preview — centered on the clamped corner, not the raw
    // pointer.
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(_bottomRightHandle));
    for (int i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(200, 200));
      await tester.pump();
    }

    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect br = tester.getRect(_bottomRightHandle);
    expect(br.center.dx, closeTo(elem.right, 1.0),
        reason: 'handle hugs the clamped right edge during resize');
    expect(br.center.dy, closeTo(elem.bottom, 1.0),
        reason: 'handle hugs the clamped bottom edge during resize');

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
