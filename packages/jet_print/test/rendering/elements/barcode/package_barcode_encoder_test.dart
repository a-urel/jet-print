import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/rendering/elements/barcode/barcode_encoder.dart';
import 'package:jet_print/src/rendering/elements/barcode/package_barcode_encoder.dart';

void main() {
  const enc = PackageBarcodeEncoder();

  BarcodeEncoded ok(BarcodeEncodeResult r) {
    expect(r, isA<BarcodeEncoded>());
    return r as BarcodeEncoded;
  }

  test('Code128 produces bars within the space', () {
    final r = ok(enc.encode(BarcodeSymbology.code128, 'ABC-123',
        width: 200, height: 80));
    expect(r.resolvedSymbology, BarcodeSymbology.code128);
    expect(r.symbol.modules, isNotEmpty);
    expect(r.symbol.isTwoD, isFalse);
    for (final m in r.symbol.modules) {
      expect(m.left >= 0 && m.left + m.width <= 200.0001, isTrue);
    }
  });

  test('EAN-13 with 12 digits auto-fixes and encodes', () {
    final r = ok(enc.encode(BarcodeSymbology.ean13, '590123412345',
        width: 200, height: 80, showText: true));
    expect(r.resolvedSymbology, BarcodeSymbology.ean13);
    expect(r.symbol.texts, isNotEmpty); // HRI text present
  });

  test('EAN-13 with letters is invalid', () {
    expect(enc.encode(BarcodeSymbology.ean13, 'ABC', width: 200, height: 80),
        isA<BarcodeInvalid>());
  });

  test('auto infers QR for a URL; 2D symbol space is square', () {
    final r = ok(enc.encode(BarcodeSymbology.auto, 'https://x.example',
        width: 120, height: 120));
    expect(r.resolvedSymbology, BarcodeSymbology.qrCode);
    expect(r.symbol.isTwoD, isTrue);
    expect(r.symbol.modules, isNotEmpty);
    // 2D coordinate space is square (squareness comes from the space, not
    // individual span dimensions).
    expect((r.symbol.spaceWidth - r.symbol.spaceHeight).abs() < 0.001, isTrue);
    expect(r.symbol.texts, isEmpty); // no HRI for 2D
  });

  test('QR ecc level changes the module count', () {
    final low = ok(enc.encode(BarcodeSymbology.qrCode, 'PAYLOAD-PAYLOAD',
        width: 120, height: 120, eccLevel: QrErrorCorrectionLevel.l));
    final high = ok(enc.encode(BarcodeSymbology.qrCode, 'PAYLOAD-PAYLOAD',
        width: 120, height: 120, eccLevel: QrErrorCorrectionLevel.h));
    expect(high.symbol.modules.length,
        greaterThanOrEqualTo(low.symbol.modules.length));
  });

  // Cheap-add 1D symbologies (encoder already in the `barcode` package): each
  // encodes its sample value to in-bounds bars, classifies as 1D, and rejects
  // a value that is invalid for it.
  final newOneD = <BarcodeSymbology, (String good, String bad)>{
    BarcodeSymbology.code93: ('CODE-93', ''),
    BarcodeSymbology.codabar: ('1234567', 'XYZ'),
    BarcodeSymbology.ean2: ('12', '123'),
    BarcodeSymbology.ean5: ('12345', '12'),
    BarcodeSymbology.gs128: ('(01)00012345678905', 'café'),
    // 'AB' is non-numeric so it survives the odd→even autofix and the encoder
    // still rejects it (a bare odd '12345' would now be padded to '012345').
    BarcodeSymbology.itf: ('1234', 'AB'),
    BarcodeSymbology.postnet: ('55555', 'ABC'),
    BarcodeSymbology.upcE: ('01234565', 'ABCDEFGH'),
    BarcodeSymbology.itf16: ('123456789012345', '12345'),
    BarcodeSymbology.isbn: ('9780306406157', 'ABC'),
    BarcodeSymbology.telepen: ('ABC123', ''),
    BarcodeSymbology.rm4scc: ('LE28HE', 'abc'),
  };
  for (final entry in newOneD.entries) {
    final s = entry.key;
    final (good, bad) = entry.value;
    test('$s encodes "$good" as in-bounds 1D bars', () {
      final r = ok(enc.encode(s, good, width: 220, height: 80));
      expect(r.resolvedSymbology, s);
      expect(r.symbol.isTwoD, isFalse, reason: '$s should be 1D');
      expect(r.symbol.modules, isNotEmpty, reason: '$s has no modules');
      for (final m in r.symbol.modules) {
        expect(m.left >= -0.001 && m.left + m.width <= 220.001, isTrue,
            reason: '$s bar out of bounds: ${m.left}..${m.left + m.width}');
      }
    });
    test('$s rejects "$bad"', () {
      expect(enc.encode(s, bad, width: 220, height: 80), isA<BarcodeInvalid>(),
          reason: '$s should reject "$bad"');
    });
  }

  test('DataMatrix / PDF417 / Aztec encode and all modules fit in space', () {
    for (final s in <BarcodeSymbology>[
      BarcodeSymbology.dataMatrix,
      BarcodeSymbology.pdf417,
      BarcodeSymbology.aztec,
    ]) {
      final r = ok(enc.encode(s, 'HELLO-036', width: 150, height: 150));
      expect(r.symbol.modules, isNotEmpty, reason: '$s has no modules');
      for (final m in r.symbol.modules) {
        expect(m.left >= -0.001, isTrue,
            reason: '$s module left=${m.left} < 0');
        expect(m.left + m.width <= r.symbol.spaceWidth + 0.001, isTrue,
            reason:
                '$s module right=${m.left + m.width} > spaceWidth=${r.symbol.spaceWidth}');
        expect(m.top >= -0.001, isTrue, reason: '$s module top=${m.top} < 0');
        expect(m.top + m.height <= r.symbol.spaceHeight + 0.001, isTrue,
            reason:
                '$s module bottom=${m.top + m.height} > spaceHeight=${r.symbol.spaceHeight}');
      }
    }
  });
}
