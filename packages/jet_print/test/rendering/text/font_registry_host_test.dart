// Registry host-font ingest (022 — contracts C4–C6; T003).
//
// `registerHostFonts`, always called AFTER `registerDefault()`, layers host
// families on top of the built-ins: additive, last-registration-wins per
// `family|weight|italic`, with the built-ins kept and `families` ordered
// built-ins-then-host-insertion-order. A regular-only host family resolves
// bold/italic to its own regular face (no throw). White-box.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/jet_font.dart';

import '../../support/test_fonts.dart';

JetFontFamily _family(String name, {required Uint8List regular}) =>
    JetFontFamily(
        name: name, faces: <JetFontFace>[JetFontFace(bytes: regular)]);

void main() {
  group('registerHostFonts — last-wins & additive (C4)', () {
    test('resolves a host family\'s bytes and metrics', () {
      final Uint8List bytes = validRegularFontBytes();
      final FontRegistry registry = FontRegistry()
        ..registerDefault()
        ..registerHostFonts(
            <JetFontFamily>[_family('Acme Brand', regular: bytes)]);
      expect(registry.bytesFor('Acme Brand'), same(bytes));
      expect(registry.metricsFor('Acme Brand'), isNotNull);
    });

    test('the same name registered twice keeps one entry, last bytes win', () {
      final Uint8List first = validRegularFontBytes();
      final Uint8List second = validItalicFontBytes(); // any other valid bytes
      final FontRegistry registry = FontRegistry()
        ..registerDefault()
        ..registerHostFonts(<JetFontFamily>[
          _family('Acme Brand', regular: first),
          // A second family under the same name: italic-bytes used as a regular
          // face is a perfectly valid regular face; last registration wins.
          JetFontFamily(
              name: 'Acme Brand',
              faces: <JetFontFace>[JetFontFace(bytes: second)]),
        ]);
      expect(registry.bytesFor('Acme Brand'), same(second));
      expect(registry.families.where((String f) => f == 'Acme Brand'),
          hasLength(1));
    });

    test('built-ins survive host ingest; an unknown family falls back', () {
      final FontRegistry registry = FontRegistry()
        ..registerDefault()
        ..registerHostFonts(<JetFontFamily>[
          _family('Acme Brand', regular: validRegularFontBytes())
        ]);
      expect(registry.hasDefault, isTrue);
      expect(registry.families, contains(FontRegistry.defaultFamily));
      // An unregistered family resolves to the default bytes.
      expect(registry.bytesFor('Nonexistent'),
          same(registry.bytesFor(FontRegistry.defaultFamily)));
    });

    test('shadowing a built-in replaces its faces but never removes default',
        () {
      final Uint8List shadow = validRegularFontBytes();
      final FontRegistry registry = FontRegistry()
        ..registerDefault()
        ..registerHostFonts(<JetFontFamily>[
          _family(FontRegistry.defaultFamily, regular: shadow)
        ]);
      // The default family's regular bytes are now the host's, but the family
      // still exists and hasDefault stays true (FR-006).
      expect(registry.bytesFor(FontRegistry.defaultFamily), same(shadow));
      expect(registry.hasDefault, isTrue);
      expect(registry.families.first, FontRegistry.defaultFamily);
    });
  });

  group('families — stable, predictable order (C5)', () {
    test('order is built-ins then host insertion order, stable on re-read', () {
      final FontRegistry registry = FontRegistry()
        ..registerDefault()
        ..registerHostFonts(<JetFontFamily>[
          _family('Acme One', regular: validRegularFontBytes()),
          _family('Acme Two', regular: validBoldFontBytes()),
        ]);
      const List<String> expected = <String>[
        FontRegistry.defaultFamily,
        'Acme One',
        'Acme Two',
      ];
      expect(registry.families, expected);
      // Re-reading does not reshuffle.
      expect(registry.families, expected);
    });
  });

  group('missing variant falls back without error (C6)', () {
    test('a regular-only host family resolves bold/italic to its regular face',
        () {
      final Uint8List regular = validRegularFontBytes();
      final FontRegistry registry = FontRegistry()
        ..registerDefault()
        ..registerHostFonts(
            <JetFontFamily>[_family('Acme Brand', regular: regular)]);
      expect(registry.bytesFor('Acme Brand', weight: JetFontWeight.bold),
          same(regular));
      expect(registry.bytesFor('Acme Brand', italic: true), same(regular));
      expect(registry.metricsFor('Acme Brand', weight: JetFontWeight.bold),
          registry.metricsFor('Acme Brand'));
    });
  });
}
