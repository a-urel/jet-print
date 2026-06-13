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

  // --- 021 format properties: underline + copyWith --------------------------
  group('JetTextStyle.underline (021 / US1)', () {
    test('defaults to false', () {
      expect(JetTextStyle.fallback.underline, isFalse);
      expect(const JetTextStyle().underline, isFalse);
    });

    test('participates in ==, hashCode, and toString', () {
      const JetTextStyle plain = JetTextStyle();
      const JetTextStyle underlined = JetTextStyle(underline: true);
      expect(plain == underlined, isFalse);
      expect(plain.hashCode == underlined.hashCode, isFalse);
      expect(underlined.toString(), contains('underline'));
      expect(const JetTextStyle(underline: true), underlined);
    });

    test('round-trips through JSON', () {
      const JetTextStyle s = JetTextStyle(underline: true);
      expect(JetTextStyle.fromJson(s.toJson()), s);
    });

    test('is written only when true; absent or non-bool reads as false', () {
      expect(const JetTextStyle(underline: true).toJson()['underline'], isTrue);
      expect(const JetTextStyle().toJson().containsKey('underline'), isFalse);
      // A pre-021 style map has no `underline` key.
      final Map<String, Object?> pre021 = const JetTextStyle().toJson();
      expect(JetTextStyle.fromJson(pre021).underline, isFalse);
      // Tolerant of a malformed value.
      expect(
          JetTextStyle.fromJson(<String, Object?>{...pre021, 'underline': 1})
              .underline,
          isFalse);
    });
  });

  group('JetTextStyle.copyWith (021 / US1)', () {
    const JetTextStyle base = JetTextStyle(
      fontFamily: 'Inter',
      fontSize: 18,
      weight: JetFontWeight.semiBold,
      italic: true,
      underline: true,
      color: JetColor(0xFF1A73E8),
      align: JetTextAlign.right,
    );

    test('with no arguments returns an equal style', () {
      expect(base.copyWith(), base);
    });

    test('replaces each field independently', () {
      expect(base.copyWith(fontFamily: 'Roboto').fontFamily, 'Roboto');
      expect(base.copyWith(fontSize: 24).fontSize, 24);
      expect(
          base.copyWith(weight: JetFontWeight.bold).weight, JetFontWeight.bold);
      expect(base.copyWith(italic: false).italic, isFalse);
      expect(base.copyWith(underline: false).underline, isFalse);
      expect(base.copyWith(color: JetColor.black).color, JetColor.black);
      expect(
          base.copyWith(align: JetTextAlign.center).align, JetTextAlign.center);
    });

    test('a replaced field leaves every other field untouched', () {
      final JetTextStyle next = base.copyWith(fontSize: 36);
      expect(next.fontFamily, base.fontFamily);
      expect(next.weight, base.weight);
      expect(next.italic, base.italic);
      expect(next.underline, base.underline);
      expect(next.color, base.color);
      expect(next.align, base.align);
    });

    test('fontFamily sentinel: omitted preserves, explicit null clears', () {
      expect(base.copyWith(fontSize: 9).fontFamily, 'Inter',
          reason: 'omitting fontFamily must NOT clear it');
      expect(base.copyWith(fontFamily: null).fontFamily, isNull,
          reason: 'an explicit null clears the family (use the default)');
    });
  });
}
