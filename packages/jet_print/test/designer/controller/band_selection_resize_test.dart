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

  // Default definition bands (addressed by stable id):
  //   'pageHeader' (furniture), 'detail' (per-row, h=200), 'pageFooter'.
  double bandHeight(JetReportDesignerController c, String id) {
    if (id == 'pageHeader') return c.definition.furniture.pageHeader!.height;
    if (id == 'pageFooter') return c.definition.furniture.pageFooter!.height;
    return c.definition.body.root.children
        .whereType<BandNode>()
        .firstWhere((BandNode n) => n.band.id == id)
        .band
        .height;
  }

  int elementCount(JetReportDesignerController c) {
    int n = 0;
    final ReportDefinition d = c.definition;
    for (final Band? b in <Band?>[
      d.furniture.pageHeader,
      d.furniture.pageFooter,
    ]) {
      if (b != null) n += b.elements.length;
    }
    for (final BandNode node in d.body.root.children.whereType<BandNode>()) {
      n += node.band.elements.length;
    }
    return n;
  }

  group('selection targets are mutually exclusive', () {
    test('selectBand replaces any element selection', () {
      final JetReportDesignerController c = make();
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(10, 10));
      expect(c.selection.singleOrNull, isNotNull);

      c.selectBand('detail');
      expect(c.selection.bandId, 'detail');
      expect(c.selection.ids, isEmpty);
      expect(c.selection.isReport, isFalse);
    });

    test('selectReport replaces a band selection, and select() clears both',
        () {
      final JetReportDesignerController c = make();
      c.selectBand('detail');
      c.selectReport();
      expect(c.selection.isReport, isTrue);
      expect(c.selection.bandId, isNull);

      c.createElement(DesignerToolType.text,
          bandId: 'pageHeader', at: const JetOffset(5, 5));
      final String id = c.selection.singleOrNull!;
      c.select(id);
      expect(c.selection.bandId, isNull);
      expect(c.selection.isReport, isFalse);
    });

    test('selectBand ignores an unknown id', () {
      final JetReportDesignerController c = make();
      c.selectReport();
      c.selectBand('ghost');
      expect(c.selection.isReport, isTrue, reason: 'unchanged on bad id');
    });
  });

  group('committed band height (undoable)', () {
    test('setBandHeight changes the model and is undoable', () {
      final JetReportDesignerController c = make();
      expect(bandHeight(c, 'detail'), 200);

      c.setBandHeight('detail', 260);
      expect(bandHeight(c, 'detail'), 260);
      expect(c.selection.bandId, 'detail',
          reason: 'the resized band stays selected');
      expect(c.canUndo, isTrue);

      c.undo();
      expect(bandHeight(c, 'detail'), 200);
      expect(c.selection.isEmpty, isTrue,
          reason: 'prior (empty) selection back');
    });

    test('setBandHeight clamps to a minimum floor', () {
      final JetReportDesignerController c = make();
      c.setBandHeight('detail', 0);
      expect(bandHeight(c, 'detail'), greaterThanOrEqualTo(8),
          reason: 'a band cannot collapse to nothing');
    });

    test('setBandHeight to the same value records no history', () {
      final JetReportDesignerController c = make();
      c.setBandHeight('detail', 200);
      expect(c.canUndo, isFalse);
    });

    // The inspector's typed height stops at the band's content, like the
    // divider drag: it cannot shrink a band past its lowest element's bottom
    // edge, so nothing ends up hanging outside its band.
    test('setBandHeight stops at the lowest element bottom', () {
      final JetReportDesignerController c = make();
      c.createElement(DesignerToolType.shape,
          bandId: 'detail', at: const JetOffset(10, 100));
      final String id = c.selection.singleOrNull!;
      c.setGeometry(id, y: 100, height: 50); // bottom edge at 150
      c.setBandHeight('detail', 60);
      expect(bandHeight(c, 'detail'), 150);
      c.setBandHeight('detail', 170); // above the content: taken as typed
      expect(bandHeight(c, 'detail'), 170);
    });

    test('content already past the bottom blocks shrinking but never grows',
        () {
      // A band of 50 whose element already reaches 100 (a loaded report, or a
      // programmatic SetBandHeightCommand, can leave it so).
      final JetReportDesignerController c = JetReportDesignerController(
        definition: const ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          body: ReportBody(
            root: DetailScope(id: 'root', children: <ScopeNode>[
              BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 50,
                elements: <ReportElement>[
                  ShapeElement(
                      id: 'tall',
                      bounds: JetRect(x: 10, y: 10, width: 40, height: 90),
                      kind: ShapeKind.rectangle),
                ],
              )),
            ]),
          ),
        ),
      );
      addTearDown(c.dispose);
      c.setBandHeight('detail', 20);
      expect(bandHeight(c, 'detail'), 50,
          reason: 'already below its content: no shrink, no forced growth');
      expect(c.canUndo, isFalse, reason: 'nothing changed, nothing recorded');
      c.setBandHeight('detail', 80); // growing is still taken as typed
      expect(bandHeight(c, 'detail'), 80);
    });
  });

  group('live band resize', () {
    test('a flow-band drag previews then commits the new height', () {
      final JetReportDesignerController c = make();
      c.beginBandResize('detail');
      expect(c.bandResizePreviewHeight('detail'), 200);

      c.updateBandResize(50); // +50pt height
      expect(c.bandResizePreviewHeight('detail'), 250);
      expect(bandHeight(c, 'detail'), 200,
          reason: 'model unchanged until commit');

      c.commitBandResize();
      expect(bandHeight(c, 'detail'), 250);
      expect(c.bandResizePreviewHeight('detail'), isNull,
          reason: 'preview cleared');
      expect(c.canUndo, isTrue);
    });

    test('cancel discards the preview without touching the model', () {
      final JetReportDesignerController c = make();
      c.beginBandResize('detail');
      c.updateBandResize(50);
      c.cancelBandResize();
      expect(c.bandResizePreviewHeight('detail'), isNull);
      expect(bandHeight(c, 'detail'), 200);
      expect(c.canUndo, isFalse);
    });

    test('a zero-delta commit records no history', () {
      final JetReportDesignerController c = make();
      c.beginBandResize('detail');
      c.updateBandResize(0);
      c.commitBandResize();
      expect(bandHeight(c, 'detail'), 200);
      expect(c.canUndo, isFalse);
    });

    test('the height floor also applies to a live shrink', () {
      final JetReportDesignerController c = make();
      c.beginBandResize('detail');
      c.updateBandResize(-1000); // way past the floor
      expect(c.bandResizePreviewHeight('detail'), greaterThanOrEqualTo(8));
    });
  });

  group('element ops no-op on a band/report selection', () {
    test('delete does nothing when a band is selected', () {
      final JetReportDesignerController c = make();
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(10, 10));
      final int before = elementCount(c);
      c.selectBand('detail');
      c.delete();
      final int after = elementCount(c);
      expect(after, before, reason: 'delete targets elements, not bands');
    });
  });
}
