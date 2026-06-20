// A resize handle stopped at a band border must simply STOP — the anchored
// (opposite) edge must not move. The move-style `clampToBand` preserved size and
// shifted position, so dragging the left handle past the left border pinned x=0
// but kept the grown width, pushing the RIGHT edge outward (as if the right handle
// had moved). A resize needs an edge-aware clamp instead.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

JetRect _bounds(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds;

double _detailBandHeight(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<BandNode>().first.band.height;

void main() {
  test('left handle clamped at the band border leaves the right edge fixed',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(10, 20));
    final String id = c.selection.singleOrNull!;
    final JetRect start = _bounds(c, id);
    final double right0 = start.x + start.width;

    c.beginResize(id, ResizeHandle.left);
    c.updateResize(const JetOffset(-200, 0)); // drag the left edge far past x=0

    final JetRect p = c.previewBoundsFor(id)!;
    expect(p.x, 0, reason: 'left edge pins at the band border');
    expect(p.x + p.width, closeTo(right0, 0.001),
        reason:
            'the right (anchored) edge must NOT move — no resize past border');
  });

  test('right handle clamped at the band border leaves the left edge fixed',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(50, 20));
    final String id = c.selection.singleOrNull!;
    final double left0 = _bounds(c, id).x;

    c.beginResize(id, ResizeHandle.right);
    c.updateResize(
        const JetOffset(2000, 0)); // drag the right edge far past max

    final JetRect p = c.previewBoundsFor(id)!;
    expect(p.x, closeTo(left0, 0.001),
        reason: 'the left (anchored) edge must NOT move');
  });

  test('bottom handle clamped at the band border leaves the top edge fixed',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(20, 5));
    final String id = c.selection.singleOrNull!;
    final double top0 = _bounds(c, id).y;

    c.beginResize(id, ResizeHandle.bottom);
    c.updateResize(const JetOffset(0, 2000)); // drag the bottom edge past max

    final JetRect p = c.previewBoundsFor(id)!;
    expect(p.y, closeTo(top0, 0.001),
        reason: 'the top (anchored) edge must NOT move');
    expect(p.y + p.height, closeTo(_detailBandHeight(c), 0.001),
        reason: 'the bottom edge pins at the band border');
  });
}
