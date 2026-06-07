import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/color.dart';

void main() {
  group('JetColor', () {
    test('fromARGB packs channels into argb', () {
      expect(const JetColor.fromARGB(0xFF, 0x1A, 0x73, 0xE8).argb, 0xFF1A73E8);
    });

    test('round-trips through an #AARRGGBB hex string', () {
      const JetColor color = JetColor(0xFF1A73E8);
      expect(color.toJson(), '#FF1A73E8');
      expect(JetColor.fromJson(color.toJson()), color);
    });

    test('accepts #RRGGBB (assumes opaque alpha)', () {
      expect(JetColor.fromJson('#1A73E8'), const JetColor(0xFF1A73E8));
    });

    test('exposes black as opaque 0xFF000000', () {
      expect(JetColor.black, const JetColor(0xFF000000));
      expect(JetColor.black.toJson(), '#FF000000');
    });

    test('has value equality', () {
      expect(const JetColor(0x80FF0000), const JetColor(0x80FF0000));
      expect(const JetColor(0x80FF0000) == const JetColor(0xFF00FF00), isFalse);
    });

    test('throws FormatException on malformed hex', () {
      expect(() => JetColor.fromJson('#12'), throwsFormatException);
      expect(() => JetColor.fromJson('#GGGGGG'), throwsFormatException);
    });
  });
}
