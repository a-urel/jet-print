import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';

void main() {
  group('JetBoxStyle', () {
    test('none has no fill/stroke and unit stroke width', () {
      expect(JetBoxStyle.none.fill, isNull);
      expect(JetBoxStyle.none.stroke, isNull);
      expect(JetBoxStyle.none.strokeWidth, 1.0);
    });

    test('round-trips a filled, stroked box', () {
      const JetBoxStyle style = JetBoxStyle(
        fill: JetColor(0x11000000),
        stroke: JetColor(0xFF000000),
        strokeWidth: 2,
      );
      expect(JetBoxStyle.fromJson(style.toJson()), style);
    });

    test('omits null fill/stroke from JSON', () {
      final Map<String, Object?> json = JetBoxStyle.none.toJson();
      expect(json.containsKey('fill'), isFalse);
      expect(json.containsKey('stroke'), isFalse);
      expect(json['strokeWidth'], 1.0);
    });

    test('has value equality', () {
      expect(
          const JetBoxStyle(strokeWidth: 3), const JetBoxStyle(strokeWidth: 3));
      expect(const JetBoxStyle(strokeWidth: 3) == JetBoxStyle.none, isFalse);
    });
  });

  // --- 021 format properties: sentinel-based copyWith -----------------------
  group('JetBoxStyle.copyWith (021 / US2)', () {
    const JetBoxStyle base = JetBoxStyle(
      fill: JetColor(0x3300FF00),
      stroke: JetColor(0xFF112233),
      strokeWidth: 2.5,
    );

    test('with no arguments returns an equal style', () {
      expect(base.copyWith(), base);
    });

    test('omitting fill/stroke preserves them', () {
      final JetBoxStyle next = base.copyWith(strokeWidth: 7);
      expect(next.fill, base.fill);
      expect(next.stroke, base.stroke);
      expect(next.strokeWidth, 7);
    });

    test('an explicit null clears fill ("no fill")', () {
      final JetBoxStyle next = base.copyWith(fill: null);
      expect(next.fill, isNull);
      expect(next.stroke, base.stroke, reason: 'stroke untouched');
      expect(next.strokeWidth, base.strokeWidth);
    });

    test('an explicit null clears stroke ("no outline")', () {
      final JetBoxStyle next = base.copyWith(stroke: null);
      expect(next.stroke, isNull);
      expect(next.fill, base.fill, reason: 'fill untouched');
    });

    test('replaces fill/stroke with new colors', () {
      final JetBoxStyle next = base.copyWith(
          fill: const JetColor(0xFFEF4444), stroke: const JetColor(0xFF000000));
      expect(next.fill, const JetColor(0xFFEF4444));
      expect(next.stroke, const JetColor(0xFF000000));
    });
  });
}
