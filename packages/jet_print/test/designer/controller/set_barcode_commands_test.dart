// Barcode controller mutators (036): symbology, data/field, and options.
//
// Black-box: drives ONLY the public controller surface (mirroring
// set_barcode_color_command_test.dart). The undoable commands behind each
// method are an implementation detail — asserted via the public element API.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _report(List<ReportElement> elements) => ReportDefinition(
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

const JetRect _bounds = JetRect(x: 0, y: 0, width: 60, height: 60);

BarcodeElement _element({String id = 'b1', String? dataField}) =>
    BarcodeElement(
      id: id,
      bounds: _bounds,
      symbology: BarcodeSymbology.code128,
      data: 'INITIAL',
      dataField: dataField,
    );

JetReportDesignerController _controller({String? dataField}) =>
    JetReportDesignerController(
      definition: _report(<ReportElement>[_element(dataField: dataField)]),
    );

void main() {
  group('setBarcodeSymbology', () {
    test('updates symbology, preserving data/bounds', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeSymbology('b1', BarcodeSymbology.ean13);
      expect(_barcode(c, 'b1').symbology, BarcodeSymbology.ean13);
      expect(_barcode(c, 'b1').data, 'INITIAL'); // preserved
      expect(_barcode(c, 'b1').bounds, _bounds);
      c.dispose();
    });

    test('is undoable', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeSymbology('b1', BarcodeSymbology.qrCode);
      expect(_barcode(c, 'b1').symbology, BarcodeSymbology.qrCode);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(_barcode(c, 'b1').symbology, BarcodeSymbology.code128);
      c.dispose();
    });

    test('a missing target is a no-op', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeSymbology('missing', BarcodeSymbology.qrCode);
      expect(_barcode(c, 'b1').symbology, BarcodeSymbology.code128);
      c.dispose();
    });
  });

  group('setBarcodeData', () {
    test('sets literal data and clears dataField', () {
      final JetReportDesignerController c = _controller(dataField: 'sku');
      c.setBarcodeData('b1', 'LITERAL');
      expect(_barcode(c, 'b1').data, 'LITERAL');
      expect(_barcode(c, 'b1').dataField, isNull);
      c.dispose();
    });

    test('clears dataField even when it was already null', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeData('b1', 'X');
      expect(_barcode(c, 'b1').dataField, isNull);
      c.dispose();
    });
  });

  group('setBarcodeDataField', () {
    test('sets the bound field and is undoable', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeDataField('b1', 'sku');
      expect(_barcode(c, 'b1').dataField, 'sku');
      expect(c.canUndo, isTrue);
      c.dispose();
    });

    test('clears the bound field when null is passed', () {
      final JetReportDesignerController c = _controller(dataField: 'sku');
      c.setBarcodeDataField('b1', null);
      expect(_barcode(c, 'b1').dataField, isNull);
      c.dispose();
    });
  });

  group('setBarcodeValue (field-or-literal single input)', () {
    test('a bare [field] token binds the data field', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeValue('b1', '[sku]');
      expect(_barcode(c, 'b1').dataField, 'sku');
      c.dispose();
    });

    test('a [field] token trims whitespace inside the brackets', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeValue('b1', '[  sku  ]');
      expect(_barcode(c, 'b1').dataField, 'sku');
      c.dispose();
    });

    test('plain text is a literal and clears any bound field', () {
      final JetReportDesignerController c = _controller(dataField: 'sku');
      c.setBarcodeValue('b1', '9501101530003');
      expect(_barcode(c, 'b1').data, '9501101530003');
      expect(_barcode(c, 'b1').dataField, isNull);
      c.dispose();
    });

    test('binding keeps the prior literal as a fallback', () {
      // _element seeds data: 'INITIAL'; binding a field must not erase it.
      final JetReportDesignerController c = _controller();
      c.setBarcodeValue('b1', '[sku]');
      expect(_barcode(c, 'b1').data, 'INITIAL');
      expect(_barcode(c, 'b1').dataField, 'sku');
      c.dispose();
    });

    test('a value that is not a bare token stays literal (no expressions)', () {
      // Brackets embedded in other text are NOT a field token → literal.
      final JetReportDesignerController c = _controller();
      c.setBarcodeValue('b1', 'SKU-[sku]-X');
      expect(_barcode(c, 'b1').data, 'SKU-[sku]-X');
      expect(_barcode(c, 'b1').dataField, isNull);
      c.dispose();
    });

    test('is undoable', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeValue('b1', '[sku]');
      expect(c.canUndo, isTrue);
      c.undo();
      expect(_barcode(c, 'b1').dataField, isNull);
      c.dispose();
    });
  });

  group('setBarcode options', () {
    test('toggles showText to false', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeShowText('b1', false);
      expect(_barcode(c, 'b1').showText, isFalse);
      c.dispose();
    });

    test('toggles quietZone to false', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeQuietZone('b1', false);
      expect(_barcode(c, 'b1').quietZone, isFalse);
      c.dispose();
    });

    test('sets QR ecc level', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeEccLevel('b1', QrErrorCorrectionLevel.h);
      expect(_barcode(c, 'b1').eccLevel, QrErrorCorrectionLevel.h);
      c.dispose();
    });

    test('omitted options are unchanged', () {
      final JetReportDesignerController c = _controller();
      c.setBarcodeShowText('b1', false);
      // quietZone and eccLevel defaults are preserved.
      expect(_barcode(c, 'b1').quietZone, isTrue);
      expect(_barcode(c, 'b1').eccLevel, QrErrorCorrectionLevel.m);
      c.dispose();
    });
  });
}
