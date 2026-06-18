import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/barcode_element_codec.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/styles/color.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('barcode', const BarcodeElementCodec());

void main() {
  group('BarcodeElement', () {
    test('is a ReportElement with the "barcode" type key and black default',
        () {
      const BarcodeElement e = BarcodeElement(
        id: 'qr',
        bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
        symbology: BarcodeSymbology.qrCode,
        data: 'https://example.com/inv/42',
      );
      expect(e, isA<ReportElement>());
      expect(e.typeKey, 'barcode');
      expect(e.color, JetColor.black);
    });

    test('default (black) color is omitted from JSON and reads back black', () {
      final ElementCodecRegistry registry = _registry();
      const BarcodeElement e = BarcodeElement(
        id: 'qr',
        bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
        symbology: BarcodeSymbology.qrCode,
        data: 'x',
      );
      expect(registry.encode(e).containsKey('color'), isFalse);
      expect(registry.decode(registry.encode(e)), e);
    });

    test('round-trips each symbology', () {
      final ElementCodecRegistry registry = _registry();
      for (final BarcodeSymbology symbology in BarcodeSymbology.values) {
        final BarcodeElement e = BarcodeElement(
          id: 'b_${symbology.name}',
          bounds: const JetRect(x: 0, y: 0, width: 60, height: 30),
          symbology: symbology,
          data: '12345678',
          color: const JetColor(0xFF202020),
        );
        expect(registry.decode(registry.encode(e)), e);
      }
    });

    test('defaults: auto symbology fields are off-by-default sensible', () {
      const el = BarcodeElement(
        id: 'b1',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        symbology: BarcodeSymbology.auto,
        data: 'X',
      );
      expect(el.dataField, isNull);
      expect(el.showText, isTrue);
      expect(el.quietZone, isTrue);
      expect(el.eccLevel, QrErrorCorrectionLevel.m);
    });

    test('copyWith replaces named fields and preserves the rest', () {
      const el = BarcodeElement(
        id: 'b1',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        symbology: BarcodeSymbology.auto,
        data: 'X',
      );
      final next = el.copyWith(
        symbology: BarcodeSymbology.ean13,
        dataField: () => 'sku',
        showText: false,
        quietZone: false,
        eccLevel: QrErrorCorrectionLevel.h,
      );
      expect(next.symbology, BarcodeSymbology.ean13);
      expect(next.dataField, 'sku');
      expect(next.showText, isFalse);
      expect(next.quietZone, isFalse);
      expect(next.eccLevel, QrErrorCorrectionLevel.h);
      expect(next.id, 'b1');
      expect(next.data, 'X');
    });

    test('copyWith can clear dataField back to null', () {
      const el = BarcodeElement(
        id: 'b1',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        symbology: BarcodeSymbology.auto,
        data: 'X',
        dataField: 'sku',
      );
      expect(el.copyWith(dataField: () => null).dataField, isNull);
      expect(el.copyWith().dataField, 'sku'); // omitted → unchanged
    });

    test('equality accounts for the new fields', () {
      const a = BarcodeElement(
          id: 'b1',
          bounds: JetRect(x: 0, y: 0, width: 1, height: 1),
          symbology: BarcodeSymbology.auto,
          data: 'X');
      const b = BarcodeElement(
          id: 'b1',
          bounds: JetRect(x: 0, y: 0, width: 1, height: 1),
          symbology: BarcodeSymbology.auto,
          data: 'X',
          showText: false);
      expect(a == b, isFalse);
    });
  });
}
