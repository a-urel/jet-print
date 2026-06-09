// Per-handle resize through the controller (US2 / T045 / FR-009/010).
// Uses threshold 0 so snapping never interferes with the pure resize geometry.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportTemplate _fixture() => const ReportTemplate(
      name: 'F',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 300,
          elements: <ReportElement>[
            TextElement(
              id: 't1',
              bounds: JetRect(x: 50, y: 50, width: 40, height: 20),
              text: 'a',
            ),
          ],
        ),
      ],
    );

JetRect _bounds(JetReportDesignerController c) =>
    c.template.bands.first.elements.first.bounds;

JetReportDesignerController _open() =>
    JetReportDesignerController()..open(_fixture());

void main() {
  test('dragging the bottom-right handle grows width and height', () {
    final JetReportDesignerController c = _open()..select('t1');
    c.beginResize('t1', ResizeHandle.bottomRight);
    c.updateResize(const JetOffset(20, 10), threshold: 0);
    c.commitResize();
    expect(_bounds(c), const JetRect(x: 50, y: 50, width: 60, height: 30));
    expect(c.canUndo, isTrue);
    c.undo();
    expect(_bounds(c), const JetRect(x: 50, y: 50, width: 40, height: 20));
    c.dispose();
  });

  test('dragging the top-left handle moves the origin and shrinks the box', () {
    final JetReportDesignerController c = _open()..select('t1');
    c.beginResize('t1', ResizeHandle.topLeft);
    c.updateResize(const JetOffset(-10, -10), threshold: 0);
    c.commitResize();
    // left/top move to 40/40; right/bottom stay at 90/70.
    expect(_bounds(c), const JetRect(x: 40, y: 40, width: 50, height: 30));
    c.dispose();
  });

  test('enforces the 4×4 minimum size on over-shrink', () {
    final JetReportDesignerController c = _open()..select('t1');
    c.beginResize('t1', ResizeHandle.bottomRight);
    c.updateResize(const JetOffset(-100, -100), threshold: 0);
    c.commitResize();
    expect(_bounds(c).width, 4);
    expect(_bounds(c).height, 4);
    c.dispose();
  });

  test('clamps an over-grow to the band ∩ page content area', () {
    final JetReportDesignerController c = _open()..select('t1');
    c.beginResize('t1', ResizeHandle.bottomRight);
    c.updateResize(const JetOffset(10000, 10000), threshold: 0);
    c.commitResize();
    const double contentWidth = 595.28 - 28.35 * 2;
    final JetRect b = _bounds(c);
    expect(b.x + b.width, lessThanOrEqualTo(contentWidth + 0.001));
    expect(b.y + b.height, lessThanOrEqualTo(300 + 0.001));
    c.dispose();
  });

  test('a resize that does not change bounds records no history', () {
    final JetReportDesignerController c = _open()..select('t1');
    c.beginResize('t1', ResizeHandle.right);
    c.updateResize(const JetOffset(0, 0), threshold: 0);
    c.commitResize();
    expect(c.canUndo, isFalse);
    c.dispose();
  });
}
