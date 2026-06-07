// jetCompare: same-type orderable comparison (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  group('jetCompare', () {
    test('orders numbers, strings and dates of the same type', () {
      expect(jetCompare(const JetNumber(1), const JetNumber(2))! < 0, isTrue);
      expect(
          jetCompare(const JetString('b'), const JetString('a'))! > 0, isTrue);
      expect(jetCompare(JetDate(DateTime(2025)), JetDate(DateTime(2026)))! < 0,
          isTrue);
      expect(jetCompare(const JetNumber(3), const JetNumber(3)), 0);
    });

    test('returns null for mismatched or non-orderable types', () {
      expect(jetCompare(const JetNumber(1), const JetString('1')), isNull);
      expect(jetCompare(const JetNull(), const JetNull()), isNull);
      expect(jetCompare(const JetBool(true), const JetBool(false)), isNull);
    });
  });
}
