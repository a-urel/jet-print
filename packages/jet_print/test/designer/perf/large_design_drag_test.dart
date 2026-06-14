// T081 — performance smoke: a multi-element drag over a large design (SC-007).
//
// Seeds 200 elements, selects 20, and live-drags them across several frames.
// The design-time canvas paints element appearance from a cached `ui.Picture`
// (Constitution IV) and the selection overlay only redraws ghosts/handles, so a
// large design must not throw and must not regress into per-frame O(n²) work.
//
// This is a SMOKE test, not a micro-benchmark: it asserts no exceptions and a
// generous wall-clock ceiling that catches a pathological blow-up without being
// flaky on slow CI. `tester.pump()` performs real layout/paint synchronously, so
// the elapsed time reflects genuine build/paint cost.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

void main() {
  testWidgets('a 20-element drag over a 200-element design stays smooth',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String detailId = firstDetailBandId(c);

    // Seed 200 elements in the detail band (positions clamp within the band).
    final List<String> ids = <String>[];
    for (int i = 0; i < 200; i++) {
      c.createElement(
        DesignerToolType.text,
        bandId: detailId,
        at: JetOffset((i % 20) * 14.0 + 4, (i ~/ 20) * 9.0 + 4),
      );
      ids.add(c.selection.singleOrNull!);
    }
    c.selectElements(ids.take(20));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'a 200-element design must build without error');
    final double startX = _elementX(c, ids.first);

    // Live-drag the 20-element selection across a dozen frames.
    final Stopwatch sw = Stopwatch()..start();
    c.beginMove();
    for (int frame = 1; frame <= 12; frame++) {
      c.updateMove(JetOffset(frame * 2.0, frame.toDouble()));
      await tester.pump(const Duration(milliseconds: 16));
    }
    c.commitMove();
    await tester.pumpAndSettle();
    sw.stop();

    expect(tester.takeException(), isNull,
        reason: 'the multi-element drag must not throw');
    expect(sw.elapsedMilliseconds, lessThan(2000),
        reason: 'twelve drag frames over 200 elements should be well under 2s; '
            'a slower run signals an O(n²)-per-frame regression');
    // The selection actually moved (the drag was real, not a no-op).
    expect(_elementX(c, ids.first), greaterThan(startX));
  });
}

double _elementX(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds
        .x;
