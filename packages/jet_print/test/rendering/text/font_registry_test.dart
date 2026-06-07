// test/rendering/text/font_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';

void main() {
  test('registerDefault wires the bundled font; metrics resolve', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    expect(reg.hasDefault, isTrue);
    final m = reg.metricsFor(null);
    expect(m.unitsPerEm, 1000);
    expect(reg.metricsFor(null).advanceForGlyph(m.glyphForCodepoint(0x41)),
        639); // 'A'
    expect(reg.bytesFor(null).isNotEmpty, isTrue);
  });

  test('unknown family falls back to the default', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    expect(reg.resolveFamily('Nope'), FontRegistry.defaultFamily);
    expect(reg.metricsFor('Nope').unitsPerEm, 1000);
  });

  test('a registered family resolves to itself', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final bytes = reg.bytesFor(null);
    reg.register('Body', bytes);
    expect(reg.resolveFamily('Body'), 'Body');
  });

  test('no default and no match throws StateError', () {
    expect(() => FontRegistry().metricsFor('x'), throwsStateError);
  });
}
