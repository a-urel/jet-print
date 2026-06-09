// The controller can select a band or the report (exclusive with element
// selection) and resize a band's height — live (preview) and committed
// (undoable). Headless; exercised through the public controller API.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  JetReportDesignerController make() {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    return c;
  }

  // Default template bands: 0 pageHeader (flow), 1 detail (flow, h=200),
  // 2 pageFooter (bottom-anchored).
  double bandHeight(JetReportDesignerController c, int i) =>
      c.template.bands[i].height;

  group('selection targets are mutually exclusive', () {
    test('selectBand replaces any element selection', () {
      final JetReportDesignerController c = make();
      c.createElement(DesignerToolType.text,
          bandIndex: 1, at: const JetOffset(10, 10));
      expect(c.selection.singleOrNull, isNotNull);

      c.selectBand(1);
      expect(c.selection.bandIndex, 1);
      expect(c.selection.ids, isEmpty);
      expect(c.selection.isReport, isFalse);
    });

    test('selectReport replaces a band selection, and select() clears both',
        () {
      final JetReportDesignerController c = make();
      c.selectBand(1);
      c.selectReport();
      expect(c.selection.isReport, isTrue);
      expect(c.selection.bandIndex, isNull);

      c.createElement(DesignerToolType.text,
          bandIndex: 0, at: const JetOffset(5, 5));
      final String id = c.selection.singleOrNull!;
      c.select(id);
      expect(c.selection.bandIndex, isNull);
      expect(c.selection.isReport, isFalse);
    });

    test('selectBand ignores an out-of-range index', () {
      final JetReportDesignerController c = make();
      c.selectReport();
      c.selectBand(99);
      expect(c.selection.isReport, isTrue, reason: 'unchanged on bad index');
    });
  });

  group('committed band height (undoable)', () {
    test('setBandHeight changes the model and is undoable', () {
      final JetReportDesignerController c = make();
      expect(bandHeight(c, 1), 200);

      c.setBandHeight(1, 260);
      expect(bandHeight(c, 1), 260);
      expect(c.selection.bandIndex, 1,
          reason: 'the resized band stays selected');
      expect(c.canUndo, isTrue);

      c.undo();
      expect(bandHeight(c, 1), 200);
      expect(c.selection.isEmpty, isTrue,
          reason: 'prior (empty) selection back');
    });

    test('setBandHeight clamps to a minimum floor', () {
      final JetReportDesignerController c = make();
      c.setBandHeight(1, 0);
      expect(bandHeight(c, 1), greaterThanOrEqualTo(8),
          reason: 'a band cannot collapse to nothing');
    });

    test('setBandHeight to the same value records no history', () {
      final JetReportDesignerController c = make();
      c.setBandHeight(1, 200);
      expect(c.canUndo, isFalse);
    });
  });

  group('live band resize', () {
    test('a flow-band drag previews then commits the new height', () {
      final JetReportDesignerController c = make();
      c.beginBandResize(1);
      expect(c.bandResizePreviewHeight(1), 200);

      c.updateBandResize(50); // +50pt height
      expect(c.bandResizePreviewHeight(1), 250);
      expect(bandHeight(c, 1), 200, reason: 'model unchanged until commit');

      c.commitBandResize();
      expect(bandHeight(c, 1), 250);
      expect(c.bandResizePreviewHeight(1), isNull, reason: 'preview cleared');
      expect(c.canUndo, isTrue);
    });

    test('cancel discards the preview without touching the model', () {
      final JetReportDesignerController c = make();
      c.beginBandResize(1);
      c.updateBandResize(50);
      c.cancelBandResize();
      expect(c.bandResizePreviewHeight(1), isNull);
      expect(bandHeight(c, 1), 200);
      expect(c.canUndo, isFalse);
    });

    test('a zero-delta commit records no history', () {
      final JetReportDesignerController c = make();
      c.beginBandResize(1);
      c.updateBandResize(0);
      c.commitBandResize();
      expect(bandHeight(c, 1), 200);
      expect(c.canUndo, isFalse);
    });

    test('the height floor also applies to a live shrink', () {
      final JetReportDesignerController c = make();
      c.beginBandResize(1);
      c.updateBandResize(-1000); // way past the floor
      expect(c.bandResizePreviewHeight(1), greaterThanOrEqualTo(8));
    });
  });

  group('element ops no-op on a band/report selection', () {
    test('delete does nothing when a band is selected', () {
      final JetReportDesignerController c = make();
      c.createElement(DesignerToolType.text,
          bandIndex: 1, at: const JetOffset(10, 10));
      final int before =
          c.template.bands.expand((ReportBand b) => b.elements).length;
      c.selectBand(1);
      c.delete();
      final int after =
          c.template.bands.expand((ReportBand b) => b.elements).length;
      expect(after, before, reason: 'delete targets elements, not bands');
    });
  });
}
