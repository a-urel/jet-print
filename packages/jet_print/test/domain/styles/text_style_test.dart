import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';

void main() {
  group('JetTextStyle', () {
    test('fallback has sensible defaults', () {
      const JetTextStyle s = JetTextStyle.fallback;
      expect(s.fontFamily, isNull);
      expect(s.fontSize, 12);
      expect(s.weight, JetFontWeight.normal);
      expect(s.italic, isFalse);
      expect(s.color, JetColor.black);
      expect(s.align, JetTextAlign.left);
    });

    test('round-trips a fully specified style', () {
      const JetTextStyle s = JetTextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        weight: JetFontWeight.bold,
        italic: true,
        color: JetColor(0xFF1A73E8),
        align: JetTextAlign.right,
      );
      expect(JetTextStyle.fromJson(s.toJson()), s);
    });

    test('omits fontFamily from JSON when null', () {
      expect(JetTextStyle.fallback.toJson().containsKey('fontFamily'), isFalse);
    });

    test('has value equality', () {
      expect(
          const JetTextStyle(fontSize: 14), const JetTextStyle(fontSize: 14));
      expect(
          const JetTextStyle(fontSize: 14) == const JetTextStyle(fontSize: 15),
          isFalse);
    });
  });
}
