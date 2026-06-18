import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/rendering/elements/barcode/symbology_inference.dart';

void main() {
  group('inferSymbology', () {
    test('URL → QR', () {
      expect(inferSymbology('https://x.example/a'), BarcodeSymbology.qrCode);
    });
    test('multiline / non-ascii / long → QR', () {
      expect(inferSymbology('a\nb'), BarcodeSymbology.qrCode);
      expect(inferSymbology('café'), BarcodeSymbology.qrCode);
      expect(inferSymbology('x' * 41), BarcodeSymbology.qrCode);
    });
    test('retail digit lengths', () {
      expect(inferSymbology('5901234123457'), BarcodeSymbology.ean13); // 13
      expect(inferSymbology('012345678905'), BarcodeSymbology.upcA); // 12
      expect(inferSymbology('96385074'), BarcodeSymbology.ean8); // 8
      expect(inferSymbology('00012345678905'), BarcodeSymbology.itf14); // 14
    });
    test('other all-digits → Code128', () {
      expect(inferSymbology('12345'), BarcodeSymbology.code128);
    });
    test('alphanumeric → Code128', () {
      expect(inferSymbology('ABC-123'), BarcodeSymbology.code128);
    });
    test('never returns auto', () {
      for (final s in <String>['', 'x', '12', 'http://a']) {
        expect(inferSymbology(s), isNot(BarcodeSymbology.auto));
      }
    });
  });

  group('resolveConcreteSymbology', () {
    test('explicit wins', () {
      expect(resolveConcreteSymbology(BarcodeSymbology.code39, '5901234123457'),
          BarcodeSymbology.code39);
    });
    test('auto infers', () {
      expect(resolveConcreteSymbology(BarcodeSymbology.auto, '5901234123457'),
          BarcodeSymbology.ean13);
    });
    test('auto + empty → QR preview default', () {
      expect(resolveConcreteSymbology(BarcodeSymbology.auto, ''),
          BarcodeSymbology.qrCode);
    });
  });

  group('isTwoDSymbology', () {
    test('classifies', () {
      expect(isTwoDSymbology(BarcodeSymbology.qrCode), isTrue);
      expect(isTwoDSymbology(BarcodeSymbology.dataMatrix), isTrue);
      expect(isTwoDSymbology(BarcodeSymbology.pdf417), isTrue);
      expect(isTwoDSymbology(BarcodeSymbology.aztec), isTrue);
      expect(isTwoDSymbology(BarcodeSymbology.code128), isFalse);
      expect(isTwoDSymbology(BarcodeSymbology.ean13), isFalse);
    });
  });
}
