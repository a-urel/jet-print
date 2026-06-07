// test/rendering/parity_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cross-backend pixel/text parity', () {
    // Deferred to spec 009: parity needs a second, structurally-different
    // backend (PdfPainter/ImagePainter). 006 proves the parity MECHANISM via the
    // line-break-determinism data goldens (measurer tests) + a Canvas smoke
    // golden. See blueprint §15.6.
  }, skip: 'cross-backend parity lands with PDF/PNG backends in spec 009');
}
