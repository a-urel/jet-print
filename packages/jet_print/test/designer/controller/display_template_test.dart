// Realtime move/resize: while a drag is in progress the *displayed* frame must
// follow the pointer, so the canvas paints element appearance at the live
// position — not frozen at the committed model until mouse-up. The committed
// `definition` still only changes on commit (one undo step per drag); the new
// `displayDefinition` is the committed definition with the in-progress drag
// baked in, and `frameVersion` ticks whenever that displayed frame changes so
// the canvas knows to re-record its cached picture.
//
// Drives the public controller only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// Every band in [d] — furniture slots plus the body's once-bands, group
/// header/footers, and per-row scope bands (recursive).
Iterable<Band> _bands(ReportDefinition d) sync* {
  for (final Band? b in <Band?>[
    d.furniture.pageHeader,
    d.furniture.pageFooter,
    d.furniture.columnHeader,
    d.furniture.columnFooter,
    d.furniture.background,
    d.body.title,
    d.body.summary,
    d.body.noData,
  ]) {
    if (b != null) yield b;
  }
  yield* _scopeBands(d.body.root);
}

Iterable<Band> _scopeBands(DetailScope scope) sync* {
  for (final GroupLevel g in scope.groups) {
    if (g.header != null) yield g.header!;
    if (g.footer != null) yield g.footer!;
  }
  for (final ScopeNode node in scope.children) {
    switch (node) {
      case BandNode(:final Band band):
        yield band;
      case NestedScope(:final DetailScope scope):
        yield* _scopeBands(scope);
    }
  }
}

JetRect _boundsIn(ReportDefinition d, String id) => _bands(d)
    .expand((Band b) => b.elements)
    .firstWhere((ReportElement e) => e.id == id)
    .bounds;

/// The blank default's first band id (the page header), which the original
/// index-0 addressing targeted.
const String _band0 = 'pageHeader';

void main() {
  test('a live move shows the moved element while the model stays put', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandId: _band0, at: const JetOffset(10, 10));
    final String id = c.selection.singleOrNull!;
    final JetRect committed = _boundsIn(c.definition, id);
    final int v0 = c.frameVersion;

    c.beginMove();
    c.updateMove(const JetOffset(20, 8));

    expect(_boundsIn(c.displayDefinition, id).x, committed.x + 20,
        reason: 'the displayed frame follows the pointer in realtime');
    expect(_boundsIn(c.displayDefinition, id).y, committed.y + 8);
    expect(_boundsIn(c.definition, id), committed,
        reason: 'the committed model is untouched until commit');
    expect(c.frameVersion, isNot(v0),
        reason: 'the canvas must know the displayed frame changed');

    c.commitMove();
    expect(_boundsIn(c.definition, id).x, committed.x + 20,
        reason: 'commit banks the move');
    expect(_boundsIn(c.displayDefinition, id), _boundsIn(c.definition, id),
        reason: 'with no drag in progress, display == committed');
  });

  test('a live resize shows the resized element while the model stays put', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    // The detail band (200pt) has room for the default square to grow into; the
    // page header (64pt) would clamp it, masking the live-resize behavior.
    c.createElement(DesignerToolType.shape,
        bandId: 'detail', at: const JetOffset(10, 10));
    final String id = c.selection.singleOrNull!;
    final JetRect committed = _boundsIn(c.definition, id);

    c.beginResize(id, ResizeHandle.bottomRight);
    c.updateResize(const JetOffset(15, 12));

    final JetRect shown = _boundsIn(c.displayDefinition, id);
    expect(shown.width, committed.width + 15,
        reason: 'the displayed frame grows with the handle in realtime');
    expect(shown.height, committed.height + 12);
    expect(_boundsIn(c.definition, id), committed,
        reason: 'the committed model is untouched until commit');

    c.commitResize();
    expect(_boundsIn(c.definition, id).width, committed.width + 15);
  });

  test(
      'a live band resize reflows the displayed frame while the model stays put',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final double committedHeight = c.definition.furniture.pageHeader!.height;
    final int v0 = c.frameVersion;

    c.beginBandResize(_band0);
    c.updateBandResize(40);

    // The canvas lays out its chrome (separators/grid/badges) from this
    // definition, so reflowing it live keeps the chrome in step with the live
    // picture.
    expect(c.bandResizePreviewHeight(_band0), committedHeight + 40,
        reason: 'the band outline previews live');
    expect(
        c.displayDefinition.furniture.pageHeader!.height, committedHeight + 40,
        reason: 'and the painted frame reflows with it, before commit');
    expect(c.definition.furniture.pageHeader!.height, committedHeight,
        reason: 'while the committed model is untouched until commit');
    expect(c.frameVersion, isNot(v0),
        reason: 'the canvas must know the displayed frame changed');

    c.commitBandResize();
    expect(c.definition.furniture.pageHeader!.height, committedHeight + 40);
    expect(
        c.displayDefinition.furniture.pageHeader!.height, committedHeight + 40);
  });

  test('cancelling a move reverts the displayed frame to the committed model',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandId: _band0, at: const JetOffset(10, 10));
    final String id = c.selection.singleOrNull!;
    final JetRect committed = _boundsIn(c.definition, id);

    c.beginMove();
    c.updateMove(const JetOffset(30, 30));
    final int vDuringDrag = c.frameVersion;
    expect(_boundsIn(c.displayDefinition, id).x, committed.x + 30);

    c.cancelMove();
    expect(_boundsIn(c.displayDefinition, id), committed,
        reason: 'the display reverts when the drag is abandoned');
    expect(c.frameVersion, isNot(vDuringDrag),
        reason: 'tearing the preview down is a displayed-frame change too');
  });
}
