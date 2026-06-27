import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/layout/panels/barcode_symbology_label.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';

void main() {
  test('returns friendly labels for representative symbologies', () {
    expect(barcodeSymbologyLabel(BarcodeSymbology.qrCode), 'QR Code');
    expect(barcodeSymbologyLabel(BarcodeSymbology.code128), 'Code 128');
    expect(barcodeSymbologyLabel(BarcodeSymbology.gs128), 'GS1-128 (EAN-128)');
    expect(barcodeSymbologyLabel(BarcodeSymbology.itf), 'Interleaved 2 of 5');
    expect(
        barcodeSymbologyLabel(BarcodeSymbology.rm4scc), 'RM4SCC (Royal Mail)');
    expect(barcodeSymbologyLabel(BarcodeSymbology.dataMatrix), 'Data Matrix');
  });

  test('every symbology has a non-empty label (exhaustive)', () {
    for (final BarcodeSymbology s in BarcodeSymbology.values) {
      expect(barcodeSymbologyLabel(s), isNotEmpty, reason: '$s has no label');
    }
  });
}
