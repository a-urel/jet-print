import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;

void main() {
  const band = Band(id: 'b', type: BandType.detail, height: 20);

  test('default band is visible', () {
    expect(band.visible, const BoolProperty());
  });

  test('copyWith sets visible, preserves others', () {
    final r = band.copyWith(visible: const BoolProperty(value: false));
    expect(r.visible, const BoolProperty(value: false));
    expect(r.id, 'b');
    expect(r.height, 20);
  });

  test('copyWith without visible preserves it', () {
    final hidden = band.copyWith(visible: const BoolProperty(expression: 'e'));
    expect(hidden.copyWith(height: 30).visible,
        const BoolProperty(expression: 'e'));
  });

  test('equality distinguishes visible', () {
    expect(
        band, isNot(band.copyWith(visible: const BoolProperty(value: false))));
  });
}
