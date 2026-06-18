// Commands: set_barcode_symbology, set_barcode_data, set_barcode_options (036).
//
// Black-box: drives commands directly via .apply() on a DesignerDocument,
// mirroring the set_barcode_color_command_test.dart harness.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/controller/commands/set_barcode_data_command.dart';
import 'package:jet_print/src/designer/controller/commands/set_barcode_options_command.dart';
import 'package:jet_print/src/designer/controller/commands/set_barcode_symbology_command.dart';
import 'package:jet_print/src/designer/controller/designer_document.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ReportDefinition _reportDef({
  String id = 'b1',
  String? dataField,
}) =>
    ReportDefinition(
      name: 'Barcode commands test',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 120,
              elements: <ReportElement>[
                BarcodeElement(
                  id: id,
                  bounds: const JetRect(x: 0, y: 0, width: 60, height: 60),
                  symbology: BarcodeSymbology.code128,
                  data: 'INITIAL',
                  dataField: dataField,
                ),
              ],
            )),
          ],
        ),
      ),
    );

DesignerDocument _docWithBarcode({String id = 'b1', String? dataField}) =>
    DesignerDocument(
      definition: _reportDef(id: id, dataField: dataField),
      selection: Selection.empty,
    );

BarcodeElement _findBarcode(DesignerDocument doc, String id) =>
    doc.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .firstWhere((ReportElement e) => e.id == id) as BarcodeElement;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SetBarcodeSymbologyCommand', () {
    test('updates symbology, preserving data/bounds/color', () {
      final doc = _docWithBarcode(id: 'b1');
      final next = SetBarcodeSymbologyCommand(
              id: 'b1', symbology: BarcodeSymbology.ean13)
          .apply(doc);
      final el = _findBarcode(next, 'b1');
      expect(el.symbology, BarcodeSymbology.ean13);
      expect(el.data, 'INITIAL'); // preserved
      expect(el.bounds, const JetRect(x: 0, y: 0, width: 60, height: 60));
    });

    test('non-barcode id is a no-op (element unchanged)', () {
      final doc = _docWithBarcode(id: 'b1');
      final next = SetBarcodeSymbologyCommand(
              id: 'missing', symbology: BarcodeSymbology.qrCode)
          .apply(doc);
      // Document still has the original element unchanged
      final el = _findBarcode(next, 'b1');
      expect(el.symbology, BarcodeSymbology.code128);
    });

    test('label is set', () {
      expect(
        const SetBarcodeSymbologyCommand(
                id: 'x', symbology: BarcodeSymbology.code128)
            .label,
        'Edit barcode symbology',
      );
    });
  });

  group('SetBarcodeDataCommand', () {
    test('sets literal data and clears dataField', () {
      final doc = _docWithBarcode(id: 'b1', dataField: 'sku');
      final next = SetBarcodeDataCommand(id: 'b1', data: 'LITERAL').apply(doc);
      final el = _findBarcode(next, 'b1');
      expect(el.data, 'LITERAL');
      expect(el.dataField, isNull);
    });

    test('clears dataField even when it was already null', () {
      final doc = _docWithBarcode(id: 'b1');
      final next = SetBarcodeDataCommand(id: 'b1', data: 'X').apply(doc);
      final el = _findBarcode(next, 'b1');
      expect(el.dataField, isNull);
    });

    test('label is set', () {
      expect(
        const SetBarcodeDataCommand(id: 'x', data: 'v').label,
        'Edit barcode data',
      );
    });
  });

  group('SetBarcodeDataFieldCommand', () {
    test('sets the bound field', () {
      final doc = _docWithBarcode(id: 'b1');
      final el = _findBarcode(
        SetBarcodeDataFieldCommand(id: 'b1', field: 'sku').apply(doc),
        'b1',
      );
      expect(el.dataField, 'sku');
    });

    test('clears the bound field when null is passed', () {
      final doc = _docWithBarcode(id: 'b1', dataField: 'sku');
      final el = _findBarcode(
        SetBarcodeDataFieldCommand(id: 'b1', field: null).apply(doc),
        'b1',
      );
      expect(el.dataField, isNull);
    });

    test('label is set', () {
      expect(
        const SetBarcodeDataFieldCommand(id: 'x', field: null).label,
        'Edit barcode field',
      );
    });
  });

  group('SetBarcodeOptionsCommand', () {
    test('toggles showText to false', () {
      final doc = _docWithBarcode(id: 'b1');
      final el = _findBarcode(
        SetBarcodeOptionsCommand(id: 'b1', showText: false).apply(doc),
        'b1',
      );
      expect(el.showText, isFalse);
    });

    test('toggles quietZone to false', () {
      final doc = _docWithBarcode(id: 'b1');
      final el = _findBarcode(
        SetBarcodeOptionsCommand(id: 'b1', quietZone: false).apply(doc),
        'b1',
      );
      expect(el.quietZone, isFalse);
    });

    test('sets QR ecc level', () {
      final doc = _docWithBarcode(id: 'b1');
      final el = _findBarcode(
        SetBarcodeOptionsCommand(id: 'b1', eccLevel: QrErrorCorrectionLevel.h)
            .apply(doc),
        'b1',
      );
      expect(el.eccLevel, QrErrorCorrectionLevel.h);
    });

    test('omitted options are unchanged', () {
      final doc = _docWithBarcode(id: 'b1');
      final el = _findBarcode(
        SetBarcodeOptionsCommand(id: 'b1', showText: false).apply(doc),
        'b1',
      );
      // quietZone and eccLevel default are preserved
      expect(el.quietZone, isTrue);
      expect(el.eccLevel, QrErrorCorrectionLevel.m);
    });

    test('label is set', () {
      expect(
        const SetBarcodeOptionsCommand(id: 'x').label,
        'Edit barcode options',
      );
    });
  });

  group('Controller dispatch', () {
    ReportDefinition report() => _reportDef(id: 'b1');

    BarcodeElement barcode(JetReportDesignerController c) =>
        c.definition.body.root.children
            .whereType<BandNode>()
            .expand((BandNode n) => n.band.elements)
            .firstWhere((ReportElement e) => e.id == 'b1') as BarcodeElement;

    test('setBarcodeSymbology dispatches and is undoable', () {
      final c = JetReportDesignerController(definition: report());
      c.setBarcodeSymbology('b1', BarcodeSymbology.qrCode);
      expect(barcode(c).symbology, BarcodeSymbology.qrCode);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(barcode(c).symbology, BarcodeSymbology.code128);
      c.dispose();
    });

    test('setBarcodeData dispatches and clears dataField', () {
      final c = JetReportDesignerController(definition: report());
      c.setBarcodeData('b1', 'NEW');
      expect(barcode(c).data, 'NEW');
      expect(barcode(c).dataField, isNull);
      c.dispose();
    });

    test('setBarcodeDataField dispatches and is undoable', () {
      final c = JetReportDesignerController(definition: report());
      c.setBarcodeDataField('b1', 'productCode');
      expect(barcode(c).dataField, 'productCode');
      expect(c.canUndo, isTrue);
      c.dispose();
    });

    test('setBarcodeShowText dispatches', () {
      final c = JetReportDesignerController(definition: report());
      c.setBarcodeShowText('b1', false);
      expect(barcode(c).showText, isFalse);
      c.dispose();
    });

    test('setBarcodeQuietZone dispatches', () {
      final c = JetReportDesignerController(definition: report());
      c.setBarcodeQuietZone('b1', false);
      expect(barcode(c).quietZone, isFalse);
      c.dispose();
    });

    test('setBarcodeEccLevel dispatches', () {
      final c = JetReportDesignerController(definition: report());
      c.setBarcodeEccLevel('b1', QrErrorCorrectionLevel.h);
      expect(barcode(c).eccLevel, QrErrorCorrectionLevel.h);
      c.dispose();
    });
  });
}
