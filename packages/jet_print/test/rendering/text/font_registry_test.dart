// test/rendering/text/font_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
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

  // --- 021 format properties: family enumeration for the picker -------------
  group('families (021 / US1 / FR-001)', () {
    test('lists the default family for a default-only registry', () {
      final FontRegistry reg = FontRegistry()..registerDefault();
      expect(reg.families, <String>[FontRegistry.defaultFamily]);
    });

    test('lists the default first, then others in insertion order', () {
      final FontRegistry reg = FontRegistry();
      final FontRegistry source = FontRegistry()..registerDefault();
      final bytes = source.bytesFor(null);
      reg.register('Zebra', bytes); // registered BEFORE the default
      reg.registerDefault();
      reg.register('Alpha', bytes);
      expect(reg.families,
          <String>[FontRegistry.defaultFamily, 'Zebra', 'Alpha'],
          reason: 'default first, then insertion order — never sorted');
    });

    test('dedupes variants of one family', () {
      final FontRegistry reg = FontRegistry()..registerDefault();
      final bytes = reg.bytesFor(null);
      reg.register('Body', bytes);
      reg.register('Body', bytes, weight: JetFontWeight.bold);
      reg.register('Body', bytes, italic: true);
      expect(reg.families, <String>[FontRegistry.defaultFamily, 'Body']);
    });
  });
}
