// Realtime move/resize: while a drag is in progress the *displayed* frame must
// follow the pointer, so the canvas paints element appearance at the live
// position — not frozen at the committed model until mouse-up. The committed
// `template` still only changes on commit (one undo step per drag); the new
// `displayTemplate` is the committed template with the in-progress drag baked in,
// and `frameVersion` ticks whenever that displayed frame changes so the canvas
// knows to re-record its cached picture.
//
// Drives the public controller only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

JetRect _boundsIn(ReportTemplate t, String id) => t.bands
    .expand((ReportBand b) => b.elements)
    .firstWhere((ReportElement e) => e.id == id)
    .bounds;

void main() {
  test('a live move shows the moved element while the model stays put', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandIndex: 0, at: const JetOffset(10, 10));
    final String id = c.selection.singleOrNull!;
    final JetRect committed = _boundsIn(c.template, id);
    final int v0 = c.frameVersion;

    c.beginMove();
    c.updateMove(const JetOffset(20, 8));

    expect(_boundsIn(c.displayTemplate, id).x, committed.x + 20,
        reason: 'the displayed frame follows the pointer in realtime');
    expect(_boundsIn(c.displayTemplate, id).y, committed.y + 8);
    expect(_boundsIn(c.template, id), committed,
        reason: 'the committed model is untouched until commit');
    expect(c.frameVersion, isNot(v0),
        reason: 'the canvas must know the displayed frame changed');

    c.commitMove();
    expect(_boundsIn(c.template, id).x, committed.x + 20,
        reason: 'commit banks the move');
    expect(_boundsIn(c.displayTemplate, id), _boundsIn(c.template, id),
        reason: 'with no drag in progress, display == committed');
  });

  test('a live resize shows the resized element while the model stays put', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.shape,
        bandIndex: 0, at: const JetOffset(10, 10));
    final String id = c.selection.singleOrNull!;
    final JetRect committed = _boundsIn(c.template, id);

    c.beginResize(id, ResizeHandle.bottomRight);
    c.updateResize(const JetOffset(15, 12));

    final JetRect shown = _boundsIn(c.displayTemplate, id);
    expect(shown.width, committed.width + 15,
        reason: 'the displayed frame grows with the handle in realtime');
    expect(shown.height, committed.height + 12);
    expect(_boundsIn(c.template, id), committed,
        reason: 'the committed model is untouched until commit');

    c.commitResize();
    expect(_boundsIn(c.template, id).width, committed.width + 15);
  });

  test(
      'a live band resize reflows the displayed frame while the model stays put',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final double committedHeight = c.template.bands[0].height;
    final int v0 = c.frameVersion;

    c.beginBandResize(0);
    c.updateBandResize(40);

    // The canvas lays out its chrome (separators/grid/badges) from this template,
    // so reflowing it live keeps the chrome in step with the live picture.
    expect(c.bandResizePreviewHeight(0), committedHeight + 40,
        reason: 'the band outline previews live');
    expect(c.displayTemplate.bands[0].height, committedHeight + 40,
        reason: 'and the painted frame reflows with it, before commit');
    expect(c.template.bands[0].height, committedHeight,
        reason: 'while the committed model is untouched until commit');
    expect(c.frameVersion, isNot(v0),
        reason: 'the canvas must know the displayed frame changed');

    c.commitBandResize();
    expect(c.template.bands[0].height, committedHeight + 40);
    expect(c.displayTemplate.bands[0].height, committedHeight + 40);
  });

  test('cancelling a move reverts the displayed frame to the committed model',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    c.createElement(DesignerToolType.text,
        bandIndex: 0, at: const JetOffset(10, 10));
    final String id = c.selection.singleOrNull!;
    final JetRect committed = _boundsIn(c.template, id);

    c.beginMove();
    c.updateMove(const JetOffset(30, 30));
    final int vDuringDrag = c.frameVersion;
    expect(_boundsIn(c.displayTemplate, id).x, committed.x + 30);

    c.cancelMove();
    expect(_boundsIn(c.displayTemplate, id), committed,
        reason: 'the display reverts when the drag is abandoned');
    expect(c.frameVersion, isNot(vDuringDrag),
        reason: 'tearing the preview down is a displayed-frame change too');
  });
}
