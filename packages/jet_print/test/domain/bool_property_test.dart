import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';

void main() {
  group('BoolProperty', () {
    test('default is visible with no expression', () {
      const p = BoolProperty();
      expect(p.value, isTrue);
      expect(p.expression, isNull);
      expect(p.hasExpression, isFalse);
    });

    test('getValue: static value used when no expression', () {
      expect(const BoolProperty(value: false).getValue((_) => true), isFalse);
      expect(const BoolProperty(value: true).getValue((_) => false), isTrue);
    });

    test('getValue: expression wins when present (precedence)', () {
      const p = BoolProperty(value: true, expression: 'x');
      expect(p.getValue((e) {
        expect(e, 'x');
        return false;
      }), isFalse);
    });

    test('copyWith thunk: omit keeps, ()=>null clears, ()=>v sets', () {
      const p = BoolProperty(value: false, expression: 'a');
      expect(p.copyWith().expression, 'a');
      expect(p.copyWith(expression: () => null).expression, isNull);
      expect(p.copyWith(expression: () => 'b').expression, 'b');
      expect(p.copyWith(value: true).value, isTrue);
    });

    test('toJson omits defaults; round-trips', () {
      expect(const BoolProperty().toJson(), <String, Object?>{});
      expect(const BoolProperty(value: false).toJson(),
          <String, Object?>{'value': false});
      expect(const BoolProperty(expression: 'q').toJson(),
          <String, Object?>{'expression': 'q'});
      const both = BoolProperty(value: false, expression: 'q');
      expect(BoolProperty.fromJson(both.toJson()), both);
    });

    test('fromJson defaults a missing value to true', () {
      expect(BoolProperty.fromJson(<String, Object?>{}), const BoolProperty());
    });

    test('equality and hashCode', () {
      expect(const BoolProperty(value: false, expression: 'a'),
          const BoolProperty(value: false, expression: 'a'));
      expect(const BoolProperty(value: false, expression: 'a').hashCode,
          const BoolProperty(value: false, expression: 'a').hashCode);
      expect(const BoolProperty(value: false),
          isNot(const BoolProperty(value: true)));
    });
  });
}
