// A multi-selection moves as a RIGID group: when the group hits a band border,
// the most-constrained element limits the whole group's delta, so every element
// moves by the same amount and relative offsets are preserved. The old per-element
// clamp let each element independently pile onto the border, collapsing the layout.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

JetRect _bounds(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds;

String _createAt(JetReportDesignerController c, double x, double y) {
  c.createElement(DesignerToolType.text, bandId: 'detail', at: JetOffset(x, y));
  return c.selection.singleOrNull!;
}

void main() {
  test('a multi-selection moved past the top border keeps its relative offsets',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final String a = _createAt(c, 20, 10); // topmost
    final String b = _createAt(c, 20, 40); // 30pt below a
    c.selectElements(<String>[a, b]);

    c.beginMove();
    c.updateMove(const JetOffset(0, -100)); // drag the group far above the band
    c.commitMove();

    final JetRect ra = _bounds(c, a);
    final JetRect rb = _bounds(c, b);
    expect(ra.y, 0, reason: 'the topmost element clamps at the band top');
    expect(rb.y - ra.y, closeTo(30, 0.001),
        reason: 'relative gap preserved — the group does NOT collapse onto the '
            'border');
  });

  test('a multi-selection clear of every border moves by the full delta', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final String a = _createAt(c, 20, 30);
    final String b = _createAt(c, 60, 50);
    c.selectElements(<String>[a, b]);

    c.beginMove();
    c.updateMove(const JetOffset(15, 10));
    c.commitMove();

    expect(_bounds(c, a).x, closeTo(35, 0.001));
    expect(_bounds(c, a).y, closeTo(40, 0.001));
    expect(_bounds(c, b).x, closeTo(75, 0.001));
    expect(_bounds(c, b).y, closeTo(60, 0.001));
  });
}
