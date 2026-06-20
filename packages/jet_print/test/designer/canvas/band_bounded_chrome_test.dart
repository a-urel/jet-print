// Spec 038: a selected element's chrome (outline + handles) must stay inside its
// band — during a clamped live move (this file's first test) and at rest when the
// element is flush against a band edge (Task 2's tests).
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
    // Mid-band element (clear of the left/top edges) so its top-left handle is a
    // clean probe, unaffected by Task 2's edge clamp.
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
    // must coincide. The top-left handle is clear of every band edge, so it is a
    // faithful "does the chrome track the element?" probe.
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect tl = tester.getRect(_topLeftHandle);
    expect(tl.center.dx, closeTo(elem.left, 1.0), reason: 'chrome tracks element x');
    expect(tl.center.dy, closeTo(elem.top, 1.0), reason: 'chrome tracks element y');

    c.commitMove();
    await tester.pumpAndSettle();
  });

  testWidgets('a flush element top-left handle stays inside the band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    // Flush at the band's top-left: the element's own rect top/left ARE the
    // band's top/left edge, so they are a faithful band-boundary probe.
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(0, 0));
    await tester.pumpAndSettle();

    final String id = c.selection.singleOrNull!;
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect tl = tester.getRect(_topLeftHandle);
    expect(tl.top, greaterThanOrEqualTo(elem.top - 0.5),
        reason: 'top handle box stays below the band top');
    expect(tl.left, greaterThanOrEqualTo(elem.left - 0.5),
        reason: 'left handle box stays right of the band left');
  });

  testWidgets('a flush element bottom-right handle stays inside the band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    // A huge offset clamps the element flush into the band's bottom-right corner.
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(1000000, 1000000));
    await tester.pumpAndSettle();

    final String id = c.selection.singleOrNull!;
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect br = tester.getRect(_bottomRightHandle);
    expect(br.bottom, lessThanOrEqualTo(elem.bottom + 0.5),
        reason: 'bottom handle box stays above the band bottom');
    expect(br.right, lessThanOrEqualTo(elem.right + 0.5),
        reason: 'right handle box stays left of the band right');
  });

  testWidgets('live resize past a band edge keeps handles on the clamped '
      'preview, inside the band', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(60, 40));
    await tester.pumpAndSettle();
    final String id = c.selection.singleOrNull!;

    // Drag the bottom-right handle far past the band's bottom-right corner and
    // HOLD (no release). The element's size clamps to the band, and the handles
    // must ride that clamped preview — not the raw pointer — staying in-band.
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(_bottomRightHandle));
    for (int i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(200, 200));
      await tester.pump();
    }

    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect br = tester.getRect(_bottomRightHandle);
    expect(br.bottom, lessThanOrEqualTo(elem.bottom + 0.5),
        reason: 'bottom handle stays above the band bottom during resize');
    expect(br.right, lessThanOrEqualTo(elem.right + 0.5),
        reason: 'right handle stays left of the band right during resize');

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
