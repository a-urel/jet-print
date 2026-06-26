import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/rendering/elements/barcode/barcode_autofix.dart';

void main() {
  test('mod10 check digit (known EAN-13 vectors)', () {
    expect(mod10CheckDigit('590123412345'), 7); // 5901234123457
    expect(mod10CheckDigit('01234567890'), 5); // UPC-A 012345678905
  });

  group('barcodeAutoFix', () {
    test('EAN-13: 12 digits → append check digit', () {
      expect(barcodeAutoFix(BarcodeSymbology.ean13, '590123412345'),
          '5901234123457');
    });
    test('EAN-13: 13 digits left unchanged', () {
      expect(barcodeAutoFix(BarcodeSymbology.ean13, '5901234123457'),
          '5901234123457');
    });
    test('EAN-8: 7 digits → append', () {
      expect(barcodeAutoFix(BarcodeSymbology.ean8, '9638507'), '96385074');
    });
    test('UPC-A: 11 digits → append', () {
      expect(
          barcodeAutoFix(BarcodeSymbology.upcA, '01234567890'), '012345678905');
    });
    test('ITF-14: 13 digits → append check digit (14 total)', () {
      expect(barcodeAutoFix(BarcodeSymbology.itf14, '0001234567890'),
          '00012345678905');
    });
    test('ITF (generic): odd digit count → left-pad to even', () {
      expect(barcodeAutoFix(BarcodeSymbology.itf, '123'), '0123');
    });
    test('ITF (generic): even digit count left unchanged', () {
      expect(barcodeAutoFix(BarcodeSymbology.itf, '1234'), '1234');
    });
    test('ITF (generic): non-numeric left unchanged (encoder will reject)', () {
      expect(barcodeAutoFix(BarcodeSymbology.itf, 'AB1'), 'AB1');
    });
    test('UPC-E / ISBN / ITF-16 / GS1-128 are not auto-repaired', () {
      // The encoder is lenient (ISBN), or repair is non-deterministic (UPC-E
      // check expansion, GS1 AI structure, ITF-16 fixed contract): pass-through.
      expect(barcodeAutoFix(BarcodeSymbology.upcE, '0123456'), '0123456');
      expect(barcodeAutoFix(BarcodeSymbology.isbn, '978030640615'),
          '978030640615');
      expect(barcodeAutoFix(BarcodeSymbology.gs128, '(01)123'), '(01)123');
    });
    test('non-numeric EAN-13 returned unchanged (encoder will reject)', () {
      expect(barcodeAutoFix(BarcodeSymbology.ean13, 'ABC'), 'ABC');
    });
    test('Code128 / QR unchanged', () {
      expect(barcodeAutoFix(BarcodeSymbology.code128, 'ABC-1'), 'ABC-1');
      expect(barcodeAutoFix(BarcodeSymbology.qrCode, 'x'), 'x');
    });
  });
}
