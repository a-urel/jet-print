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
}
