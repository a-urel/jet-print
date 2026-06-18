import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/elements/barcode/barcode_symbol.dart';

void main() {
  test('BarcodeModule value equality', () {
    expect(const BarcodeModule(0, 0, 1, 2), const BarcodeModule(0, 0, 1, 2));
    expect(const BarcodeModule(0, 0, 1, 2) == const BarcodeModule(0, 0, 1, 3),
        isFalse);
  });

  test('BarcodeSymbol holds geometry', () {
    const sym = BarcodeSymbol(
      modules: <BarcodeModule>[BarcodeModule(0, 0, 1, 10)],
      texts: <BarcodeHriText>[],
      spaceWidth: 20,
      spaceHeight: 10,
      isTwoD: false,
    );
    expect(sym.modules, hasLength(1));
    expect(sym.isTwoD, isFalse);
  });
}
