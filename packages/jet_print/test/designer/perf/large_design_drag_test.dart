// performance smoke: a multi-element drag over a large design.
//
// Seeds 200 elements, selects 20, and live-drags them across several frames.
// The design-time canvas paints element appearance from a cached `ui.Picture`
// and the selection overlay only redraws ghosts/handles, so a
// large design must not throw and must not regress into per-frame O(n²) work.
//
// This is a SMOKE test, not a micro-benchmark: it asserts no exceptions, that
// the drag really moved something, and a wall-clock ceiling far above anything
// a healthy run produces. `tester.pump()` performs real layout/paint
// synchronously, so the elapsed time is genuine build/paint cost — but it is
// ALSO genuine machine load, and that is the part to keep in mind before
// tightening the ceiling.
//
// The ceiling was 2000ms and flaked. Measured on an idle 12-core machine the
// same unchanged code took 839-1688ms; under one concurrent suite 1285-1844ms;
// under two suites plus CPU hogs 992-2193ms. A 2.6x spread with no code change
// put 2000 inside the measurement's own noise band, so the assertion was
// reporting how busy the machine was. The cost is ~60-140ms on EVERY one of the
// twelve frames — there is no warm-up cliff to skip past, so a warm-up would not
// have helped; the noise is per-frame and multiplies by twelve.
//
// Hence a ceiling ~4x the worst observed run. It is a catastrophe tripwire, not
// a performance assertion: an O(n^2)-per-frame regression at n=200 costs orders
// of magnitude, not a factor of four, so nothing that this test was ever able to
// detect has been given up. What a slower run does NOT tell you is that the code
// got slower — that needs a measurement that cancels machine speed, such as
// comparing per-frame cost at two element counts, which this test does not do.
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
    expect(sw.elapsedMilliseconds, lessThan(8000),
        reason: 'twelve drag frames over 200 elements blew past a ceiling set '
            '~4x above the slowest run ever measured on a loaded machine. This '
            'is not "the machine is busy" — that was the old 2000ms ceiling, '
            'which flaked. This is a pathological blow-up: look for per-frame '
            'work that scales with the element count.');
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
