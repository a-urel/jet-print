// Controller setBarcodeColor() unit tests (021 / US3 / contracts C8, C9).
//
// Black-box: drives only the public controller surface. setBarcodeColor() is
// the single undoable mutator behind the barcode color row. Same matrix as
// the other style mutators: one history step + one notification per real
// change; strict no-op (no history, no notify) for a missing target, a
// non-barcode target, or an equal color.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _report(List<ReportElement> elements) => ReportDefinition(
      name: 'Barcode color test',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 120,
                elements: elements)),
          ],
        ),
      ),
    );

BarcodeElement _barcode(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .firstWhere((ReportElement e) => e.id == id) as BarcodeElement;

const JetRect _bounds = JetRect(x: 12, y: 8, width: 40, height: 40);

const BarcodeElement _element = BarcodeElement(
  id: 'b',
  bounds: _bounds,
  symbology: BarcodeSymbology.qrCode,
  data: '42',
);

void main() {
  group('setBarcodeColor — replaces the color (C8)', () {
    test('a commit replaces the color, preserving symbology/data/bounds', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      c.setBarcodeColor('b', const JetColor(0xFF1E40AF));
      expect(_barcode(c, 'b').color, const JetColor(0xFF1E40AF));
      expect(_barcode(c, 'b').symbology, BarcodeSymbology.qrCode);
      expect(_barcode(c, 'b').data, '42');
      expect(_barcode(c, 'b').bounds, _bounds);
      c.dispose();
    });

    test('a real change is a single notifying, undoable step', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setBarcodeColor('b', const JetColor(0xFFEF4444));

      expect(notifications, 1);
      expect(c.canUndo, isTrue);
      c.dispose();
    });
  });

  group('setBarcodeColor — no-ops (C9 / FR-013)', () {
    test('an equal color records no history and notifies no one', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setBarcodeColor('b', JetColor.black); // already the default black

      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      c.dispose();
    });

    test('a missing target is a no-op', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setBarcodeColor('nope', const JetColor(0xFFEF4444));

      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      c.dispose();
    });

    test('a non-barcode target is a no-op', () {
      final JetReportDesignerController c = JetReportDesignerController(
        definition: _report(const <ReportElement>[
          _element,
          TextElement(id: 't', bounds: _bounds, text: 'Hi'),
        ]),
      );
      int notifications = 0;
      c.addListener(() => notifications++);

      c.setBarcodeColor('t', const JetColor(0xFFEF4444));

      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      c.dispose();
    });
  });

  group('setBarcodeColor — undo / redo (C9)', () {
    test('one undo restores black; one redo reapplies the pick', () {
      final JetReportDesignerController c = JetReportDesignerController(
          definition: _report(const <ReportElement>[_element]));
      c.setBarcodeColor('b', const JetColor(0xFF1E40AF));

      c.undo();
      expect(_barcode(c, 'b').color, JetColor.black);

      c.redo();
      expect(_barcode(c, 'b').color, const JetColor(0xFF1E40AF));
      c.dispose();
    });
  });
}
