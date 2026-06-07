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
  });
}
