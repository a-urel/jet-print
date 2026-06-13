// Public font value-type validation (022 — contracts C1–C3; T002).
//
// JetFontFace is a plain descriptor (bytes + weight + italic, value-equal by
// bytes identity). JetFontFamily validates its faces EAGERLY and SYNCHRONOUSLY
// at construction: a host assembling a bad font is rejected at the natural
// point, so neither widget build() nor render() can throw later (FR-010 /
// SC-006). White-box: imports the bundled byte fixtures via the support helper.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/text/font_format_exception.dart';
import 'package:jet_print/src/rendering/text/jet_font.dart';

import '../../support/test_fonts.dart';

void main() {
  group('JetFontFace — descriptor & defaults (C1)', () {
    test('defaults to normal weight, upright', () {
      final JetFontFace face = JetFontFace(bytes: validRegularFontBytes());
      expect(face.weight, JetFontWeight.normal);
      expect(face.italic, isFalse);
    });

    test('value equality is over (bytes identity, weight, italic)', () {
      final Uint8List bytes = validRegularFontBytes();
      expect(JetFontFace(bytes: bytes), JetFontFace(bytes: bytes));
      expect(
        JetFontFace(bytes: bytes).hashCode,
        JetFontFace(bytes: bytes).hashCode,
      );
      // Differs on weight, on italic, and on a different byte instance.
      expect(JetFontFace(bytes: bytes),
          isNot(JetFontFace(bytes: bytes, weight: JetFontWeight.bold)));
      expect(JetFontFace(bytes: bytes),
          isNot(JetFontFace(bytes: bytes, italic: true)));
      expect(JetFontFace(bytes: bytes),
          isNot(JetFontFace(bytes: validBoldFontBytes())));
    });
  });

  group('JetFontFamily — accepts valid fonts (C2)', () {
    test('a regular-only family is valid (bold/italic optional)', () {
      final JetFontFamily family = JetFontFamily(
        name: 'Acme Brand',
        faces: <JetFontFace>[JetFontFace(bytes: validRegularFontBytes())],
      );
      expect(family.name, 'Acme Brand');
      expect(family.faces, hasLength(1));
    });

    test('a full four-face family preserves its faces in order', () {
      final List<JetFontFace> faces = <JetFontFace>[
        JetFontFace(bytes: validRegularFontBytes()),
        JetFontFace(bytes: validBoldFontBytes(), weight: JetFontWeight.bold),
        JetFontFace(bytes: validItalicFontBytes(), italic: true),
        JetFontFace(
            bytes: validBoldFontBytes(),
            weight: JetFontWeight.bold,
            italic: true),
      ];
      final JetFontFamily family =
          JetFontFamily(name: 'Acme Brand', faces: faces);
      expect(family.faces, orderedEquals(faces));
    });
  });

  group('JetFontFamily — rejects bad input, synchronously (C3)', () {
    test('an empty name throws ArgumentError', () {
      expect(
        () => JetFontFamily(
          name: '',
          faces: <JetFontFace>[JetFontFace(bytes: validRegularFontBytes())],
        ),
        throwsArgumentError,
      );
    });

    test('no regular face throws FontFormatException naming the family', () {
      expect(
        () => JetFontFamily(
          name: 'Acme Brand',
          faces: <JetFontFace>[
            JetFontFace(bytes: validItalicFontBytes(), italic: true),
          ],
        ),
        throwsA(
          isA<FontFormatException>()
              .having((FontFormatException e) => e.message, 'message',
                  contains('Acme Brand'))
              .having((FontFormatException e) => e.message, 'message',
                  contains('regular')),
        ),
      );
    });

    test('empty face bytes throw FontFormatException naming the family', () {
      expect(
        () => JetFontFamily(
          name: 'Acme Brand',
          faces: <JetFontFace>[JetFontFace(bytes: emptyFontBytes())],
        ),
        throwsA(isA<FontFormatException>().having(
            (FontFormatException e) => e.message,
            'message',
            contains('Acme Brand'))),
      );
    });

    test(
        'a malformed bold face throws FontFormatException naming the family '
        'and the offending weight/italic', () {
      expect(
        () => JetFontFamily(
          name: 'Acme Brand',
          faces: <JetFontFace>[
            JetFontFace(bytes: validRegularFontBytes()),
            JetFontFace(
                bytes: malformedFontBytes(), weight: JetFontWeight.bold),
          ],
        ),
        throwsA(
          isA<FontFormatException>()
              .having((FontFormatException e) => e.message, 'message',
                  contains('Acme Brand'))
              .having((FontFormatException e) => e.message, 'message',
                  contains('bold')),
        ),
      );
    });

    test('a duplicate (weight, italic) throws ArgumentError', () {
      expect(
        () => JetFontFamily(
          name: 'Acme Brand',
          faces: <JetFontFace>[
            JetFontFace(bytes: validRegularFontBytes()),
            JetFontFace(bytes: validBoldFontBytes()), // also normal/upright
          ],
        ),
        throwsArgumentError,
      );
    });

    test('all rejections are synchronous (catchable at construction)', () {
      // No async escape: a try/catch around the constructor catches it.
      Object? caught;
      try {
        JetFontFamily(
          name: 'Acme Brand',
          faces: <JetFontFace>[JetFontFace(bytes: malformedFontBytes())],
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<FontFormatException>());
    });
  });
}
