// Undo, redo and open() cancel a drag that is in progress.
//
// Regression (#57): replacing the document left the live move/resize state set.
// Ctrl+Z works mid-drag (the shell-level shortcuts), so dragging B and undoing
// restored A's selection with B's drag still pending — and the release then
// moved A, and the commit wiped the redo entry.
//
// Drives the public controller only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

const JetRect _a0 = JetRect(x: 10, y: 10, width: 20, height: 20);
const JetRect _b0 = JetRect(x: 100, y: 10, width: 20, height: 20);

ReportDefinition _fixture() => const ReportDefinition(
      name: 'Drag',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
            id: 'detail',
            type: BandType.detail,
            height: 200,
            elements: <ReportElement>[
              ShapeElement(id: 'a', bounds: _a0, kind: ShapeKind.rectangle),
              ShapeElement(id: 'b', bounds: _b0, kind: ShapeKind.rectangle),
            ],
          )),
        ]),
      ),
    );

Band _band(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<BandNode>().single.band;

JetRect _bounds(JetReportDesignerController c, String id) =>
    _band(c).elements.firstWhere((ReportElement e) => e.id == id).bounds;

/// A controller with one history entry (A moved right by 5), and B selected —
/// ready for B to be dragged.
JetReportDesignerController _afterMovingA() {
  final JetReportDesignerController c =
      JetReportDesignerController(definition: _fixture());
  addTearDown(c.dispose);
  c.select('a');
  c.moveBy(const JetOffset(5, 0));
  c.select('b');
  return c;
}

void main() {
  test('undo mid-move cancels the move; the release moves nothing', () {
    final JetReportDesignerController c = _afterMovingA();
    c.beginMove();
    c.updateMove(const JetOffset(30, 0));

    c.undo();
    expect(c.moveDelta, isNull, reason: 'the live move is cancelled');
    c.commitMove(); // the pointer-up that follows

    expect(_bounds(c, 'a'), _a0, reason: 'A is where undo put it');
    expect(_bounds(c, 'b'), _b0, reason: 'B never moved');
    expect(c.canRedo, isTrue, reason: 'the redo entry survives the release');
  });

  test('redo mid-move cancels the move', () {
    final JetReportDesignerController c = _afterMovingA();
    c.undo();
    c.select('b');
    c.beginMove();
    c.updateMove(const JetOffset(30, 0));

    c.redo();
    c.commitMove();

    expect(_bounds(c, 'a'), const JetRect(x: 15, y: 10, width: 20, height: 20));
    expect(_bounds(c, 'b'), _b0);
  });

  test('undo mid-resize cancels the resize', () {
    final JetReportDesignerController c = _afterMovingA();
    c.beginResize('b', ResizeHandle.bottomRight);
    c.updateResize(const JetOffset(15, 15));

    c.undo();
    c.commitResize();

    expect(_bounds(c, 'a'), _a0);
    expect(_bounds(c, 'b'), _b0);
    expect(c.canRedo, isTrue);
  });

  test('undo mid-band-resize cancels the band resize', () {
    final JetReportDesignerController c = _afterMovingA();
    c.beginBandResize('detail');
    c.updateBandResize(50);

    c.undo();
    c.commitBandResize();

    expect(_band(c).height, 200);
    expect(c.canRedo, isTrue);
  });

  test('open() mid-move cancels the move', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _fixture());
    addTearDown(c.dispose);
    c.select('b');
    c.beginMove();
    c.updateMove(const JetOffset(30, 0));

    c.open(_fixture());
    expect(c.moveDelta, isNull, reason: 'the live move is cancelled');
    c.commitMove();

    expect(_bounds(c, 'b'), _b0);
    expect(c.canUndo, isFalse, reason: 'a fresh document has no history');
  });
}
