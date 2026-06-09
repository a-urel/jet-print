// Snapping behavior through the controller's resize/move interaction
// (US2 / T043 + T046a / FR-011 / SC-004). grid step = 8 pt; threshold here = 6 pt.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

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
      // right edge 90 + drag 5 = 95 → nearest grid multiple 96 (threshold 6).
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1');
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(5, 0), threshold: 6);
      expect(c.previewBoundsFor('t1')!.width, 46); // right snapped 95 → 96
      expect(c.activeGuides, isNotEmpty);
      c.dispose();
    });

    test('grid disabled suppresses grid snap (no sibling nearby)', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1');
      c.setGridEnabled(false);
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(5, 0), threshold: 6);
      expect(c.previewBoundsFor('t1')!.width, 45); // raw, no snap
      expect(c.activeGuides, isEmpty);
      c.dispose();
    });

    test('bypassSnap (Alt) places freely', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1');
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(5, 0), threshold: 6, bypassSnap: true);
      expect(c.previewBoundsFor('t1')!.width, 45);
      c.dispose();
    });

    test('snapEnabled == false suppresses all snapping', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1');
      c.setSnapEnabled(false);
      c.beginResize('t1', ResizeHandle.right);
      c.updateResize(const JetOffset(5, 0), threshold: 6);
      expect(c.previewBoundsFor('t1')!.width, 45);
      c.dispose();
    });

    test('snaps the right edge to a sibling left edge even with grid off', () {
      // t1 right 90 + drag 112 = 202 → sibling 's1'.left 203 (dist 1 ≤ 6).
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_pair())
        ..select('t1');
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
      // x 50 + drag 5 = 55 → grid 56; element commits at x = 56.
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_single())
        ..select('t1');
      c.beginMove();
      c.updateMove(const JetOffset(5, 0), threshold: 6);
      expect(c.activeGuides, isNotEmpty);
      c.commitMove();
      expect(c.template.bands.first.elements.first.bounds.x, 56);
      c.dispose();
    });
  });
}
