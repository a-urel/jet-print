// Confirms the barcode-symbology gallery is pristine under the library
// validator. Public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/barcode_gallery_sample.dart';

void main() {
  test(
      'barcodeGalleryDefinition() is pristine under the library validator '
      '(no diagnostics)', () {
    expect(validate(barcodeGalleryDefinition()), isEmpty);
  });
}
