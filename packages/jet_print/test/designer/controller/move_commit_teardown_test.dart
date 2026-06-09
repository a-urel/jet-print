// Regression: a move whose committed position is unchanged (the drag is fully
// absorbed by band clamping) must still notify listeners, so the overlay
// repaints and tears down the live snap guides + move ghost.
//
// Before the fix, `commitMove` cleared the guide state in memory but delegated
// the repaint to the move command; a clamped no-op move produces an unchanged
// template, `_commit` short-circuits it without notifying, and the last-painted
// red snap guide stayed frozen on the canvas with no drag in progress.
//
// Drives the public controller only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

JetRect _boundsOf(JetReportDesignerController c, String id) => c.template.bands
    .expand((ReportBand b) => b.elements)
    .firstWhere((ReportElement e) => e.id == id)
    .bounds;

void main() {
  test('a move clamped to a no-op still repaints and clears the guide', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);

    // Band-edge snapping only (grid off) makes the guide deterministic.
    c.setGridEnabled(false);
    c.createElement(DesignerToolType.text,
        bandIndex: 0, at: const JetOffset(0, 0));
    final String id = c.selection.singleOrNull!;
    final double bandHeight = c.template.bands[0].height;
    final JetRect b0 = _boundsOf(c, id);

    // Pin the element to the bottom-left corner of its band.
    c.setGeometry(id, x: 0, y: bandHeight - b0.height);
    final JetRect pinned = _boundsOf(c, id);

    // Drag: +x snaps the left edge back onto the band edge (raising a guide);
    // +y is wholly absorbed by the bottom clamp, so the position is unchanged.
    c.beginMove();
    c.updateMove(const JetOffset(3, 80), threshold: 6);
    expect(c.activeGuides, isNotEmpty,
        reason: 'the left edge snapping to the band edge should raise a guide');

    int repaints = 0;
    c.addListener(() => repaints++);
    c.commitMove();

    expect(repaints, greaterThan(0),
        reason: 'a clamped no-op commit must still notify so the guide clears');
    expect(c.activeGuides, isEmpty, reason: 'the guide must be torn down');
    expect(c.moveDelta, isNull, reason: 'the move ghost must be torn down');
    expect(_boundsOf(c, id), pinned,
        reason: 'the position is unchanged (no-op)');
  });
}
