// JetValue sealed model: lift, equality, stringify (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  group('JetValue.from', () {
    test('lifts null/bool/int/double/String/DateTime', () {
      expect(JetValue.from(null), isA<JetNull>());
      expect(JetValue.from(true), const JetBool(true));
      expect(JetValue.from(5), const JetNumber(5)); // int -> double
      expect(JetValue.from(2.5), const JetNumber(2.5));
      expect(JetValue.from('hi'), const JetString('hi'));
      final DateTime d = DateTime(2026, 6, 7);
      expect(JetValue.from(d), JetDate(d));
    });

    test('is idempotent on an existing JetValue', () {
      expect(JetValue.from(const JetNumber(1)), const JetNumber(1));
    });

    test('maps an unsupported runtime type to a JetError', () {
      expect(JetValue.from(<int>[1]), isA<JetError>());
    });
  });

  group('JetValue equality', () {
    test('JetNull values are all equal', () {
      expect(const JetNull(), const JetNull());
      expect(const JetNull().hashCode, const JetNull().hashCode);
    });

    test('value variants compare by contained value', () {
      expect(const JetNumber(3), const JetNumber(3));
      expect(const JetNumber(3) == const JetNumber(4), isFalse);
      expect(const JetString('a') == const JetString('b'), isFalse);
      expect(const JetBool(true) == const JetBool(false), isFalse);
    });

    test('different variants are never equal', () {
      expect(const JetNumber(1) == const JetString('1'), isFalse);
      expect(const JetNull() == const JetBool(false), isFalse);
    });

    test('JetError compares by message', () {
      expect(const JetError('x'), const JetError('x'));
      expect(const JetError('x') == const JetError('y'), isFalse);
    });
  });

  group('jetStringify', () {
    test('renders each variant', () {
      expect(jetStringify(const JetNull()), '');
      expect(jetStringify(const JetBool(true)), 'true');
      expect(jetStringify(const JetNumber(5)), '5.0'); // all-double model
      expect(jetStringify(const JetString('hi')), 'hi');
      expect(jetStringify(JetDate(DateTime(2026, 6, 7))),
          DateTime(2026, 6, 7).toIso8601String());
      expect(jetStringify(const JetError('boom')), '!ERR');
    });
  });
}
