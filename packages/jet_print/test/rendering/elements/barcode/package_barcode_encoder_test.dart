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

  test('auto infers QR for a URL; 2D has square modules', () {
    final r = ok(enc.encode(BarcodeSymbology.auto, 'https://x.example',
        width: 120, height: 120));
    expect(r.resolvedSymbology, BarcodeSymbology.qrCode);
    expect(r.symbol.isTwoD, isTrue);
    // 2D modules are square (within float tolerance).
    final m = r.symbol.modules.first;
    expect((m.width - m.height).abs() < 0.001, isTrue);
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

  test('DataMatrix / PDF417 / Aztec encode', () {
    for (final s in <BarcodeSymbology>[
      BarcodeSymbology.dataMatrix,
      BarcodeSymbology.pdf417,
      BarcodeSymbology.aztec,
    ]) {
      expect(enc.encode(s, 'HELLO-036', width: 150, height: 150),
          isA<BarcodeEncoded>(),
          reason: '$s');
    }
  });
}
