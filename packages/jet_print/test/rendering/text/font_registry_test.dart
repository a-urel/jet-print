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

  // --- 021 follow-up: the bundled default ships all four faces so B/I/U
  // render visibly on canvas AND export (same registry feeds both).
  group('registerDefault — four bundled variants', () {
    test('bold, italic, and bold-italic resolve to their own byte sources', () {
      final FontRegistry reg = FontRegistry()..registerDefault();
      final regular = reg.bytesFor(null);
      final bold = reg.bytesFor(null, weight: JetFontWeight.bold);
      final italic = reg.bytesFor(null, italic: true);
      final boldItalic =
          reg.bytesFor(null, weight: JetFontWeight.bold, italic: true);

      expect(identical(bold, regular), isFalse,
          reason: 'bold must not fall back to the regular face');
      expect(identical(italic, regular), isFalse,
          reason: 'italic must not fall back to the regular face');
      expect(identical(boldItalic, regular), isFalse);
      expect(identical(boldItalic, bold), isFalse);
      expect(identical(boldItalic, italic), isFalse);
    });

    test('every variant parses metrics with the same unitsPerEm', () {
      final FontRegistry reg = FontRegistry()..registerDefault();
      expect(reg.metricsFor(null, weight: JetFontWeight.bold).unitsPerEm, 1000);
      expect(reg.metricsFor(null, italic: true).unitsPerEm, 1000);
      expect(
          reg
              .metricsFor(null, weight: JetFontWeight.bold, italic: true)
              .unitsPerEm,
          1000);
    });

    test('intermediate weights still fall back to the regular face', () {
      final FontRegistry reg = FontRegistry()..registerDefault();
      expect(
          identical(reg.bytesFor(null, weight: JetFontWeight.medium),
              reg.bytesFor(null)),
          isTrue,
          reason: 'medium/semiBold have no bundled face — regular renders');
    });

    test('the variants stay one family in the picker enumeration', () {
      final FontRegistry reg = FontRegistry()..registerDefault();
      expect(reg.families, <String>[FontRegistry.defaultFamily]);
    });

    test('a bytes override registers that face only (the test seam)', () {
      final FontRegistry source = FontRegistry()..registerDefault();
      final FontRegistry reg = FontRegistry()
        ..registerDefault(bytes: source.bytesFor(null));
      // The override IS the regular face; bold falls back to it.
      expect(
          identical(reg.bytesFor(null, weight: JetFontWeight.bold),
              reg.bytesFor(null)),
          isTrue);
    });
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
      expect(
          reg.families, <String>[FontRegistry.defaultFamily, 'Zebra', 'Alpha'],
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
