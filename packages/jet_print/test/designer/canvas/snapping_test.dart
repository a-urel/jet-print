// Snapping behavior through the controller's resize/move interaction
// (US2 / FR-009 / SC-003). Grid step = 5 mm (kGridStep ≈ 14.173 pt, spec 015);
// threshold here = 6 pt. Expected snapped coordinates are expressed as multiples
// of kGridStep so they track the constant rather than a hardcoded literal.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// The 5 mm grid/snap step in points (mirrors the library's internal
/// `kGridStep = kGridStepMm · 72/25.4`). Defined locally so this stays a
/// black-box test that imports only the public entry point.
const double kGridStep = 5 * 72 / 25.4;

ReportTemplate _single() => const ReportTemplate(
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

// Two elements; 's1' has a non-grid left edge (203) to isolate sibling snap.
ReportTemplate _pair() => const ReportTemplate(
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
                text: 'a'),
            TextElement(
                id: 's1',
                bounds: JetRect(x: 203, y: 50, width: 40, height: 20),
                text: 'b'),
          ],
        ),
      ],
    );

void main() {
  group('resize snapping', () {
    test('snaps the right edge to the nearest grid line and shows a guide', () {
      // right edge 90 + drag 5 = 95 → nearest 5 mm line 7·kGridStep ≈ 99.21
      // (dist ≈ 4.21 ≤ threshold 6).
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1')
        ..setSnapEnabled(true);
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(5, 0), threshold: 6);
      // width = right(7·kGridStep) − left(50).
      expect(
          c.previewBoundsFor('t1')!.width, closeTo(7 * kGridStep - 50, 1e-9));
      expect(c.activeGuides, isNotEmpty);
      c.dispose();
    });

    test('C4.4 snap on with the grid HIDDEN still snaps to the grid', () {
      // Decoupling (FR-010 / D3): `gridEnabled` is visibility-only, so hiding
      // the grid must NOT suppress snapping — the magnet alone governs it. This
      // INVERTS the pre-015 assertion that grid-off disabled grid snapping.
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1')
        ..setSnapEnabled(true);
      c.setGridEnabled(false); // hide the grid; snapping must be unaffected
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(5, 0), threshold: 6);
      // right 95 still snaps to 7·kGridStep ≈ 99.21 even though the grid is off.
      expect(
          c.previewBoundsFor('t1')!.width, closeTo(7 * kGridStep - 50, 1e-9));
      expect(c.activeGuides, isNotEmpty);
      c.dispose();
    });

    test('bypassSnap (Alt) places freely', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1')
        ..setSnapEnabled(true);
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(5, 0), threshold: 6, bypassSnap: true);
      expect(c.previewBoundsFor('t1')!.width, 45);
      c.dispose();
    });

    test('snapEnabled == false suppresses all snapping', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1')
        ..setSnapEnabled(true);
      c.setSnapEnabled(false);
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(5, 0), threshold: 6);
      expect(c.previewBoundsFor('t1')!.width, 45);
      c.dispose();
    });

    test('snaps the right edge to a sibling left edge (grid hidden)', () {
      // t1 right 90 + drag 112 = 202 → sibling 's1'.left 203 (dist 1) beats the
      // nearest 5 mm line 14·kGridStep ≈ 198.43 (dist ≈ 3.57). The grid is hidden
      // (visibility-only) yet snapping still resolves to the closer sibling edge.
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_pair())
        ..select('t1')
        ..setSnapEnabled(true);
      c.setGridEnabled(false);
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(112, 0), threshold: 6);
      // width = 203 - 50 = 153.
      expect(c.previewBoundsFor('t1')!.width, 153);
      expect(c.activeGuides, isNotEmpty);
      c.dispose();
    });
  });

  group('move snapping', () {
    test('snaps the moved origin to the grid', () {
      // x 50 + drag 5 = 55 → nearest 5 mm line 4·kGridStep ≈ 56.69.
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1')
        ..setSnapEnabled(true);
      c.beginMove();
      c.updateMove(const JetOffset(5, 0), threshold: 6);
      expect(c.activeGuides, isNotEmpty);
      c.commitMove();
      expect(c.template.bands.first.elements.first.bounds.x,
          closeTo(4 * kGridStep, 1e-9));
      c.dispose();
    });
  });
}
