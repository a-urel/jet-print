import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/scope_total.dart';

void main() {
  group('ScopeTotal', () {
    test('is value-equal by (name, expression)', () {
      const ScopeTotal a = ScopeTotal('orderTotal', r'SUM($F{lineTotal})');
      const ScopeTotal b = ScopeTotal('orderTotal', r'SUM($F{lineTotal})');
      const ScopeTotal c = ScopeTotal('x', r'SUM($F{lineTotal})');
      const ScopeTotal d = ScopeTotal('orderTotal', r'SUM($F{other})');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('toString includes both name and expression', () {
      const ScopeTotal a = ScopeTotal('orderTotal', r'SUM($F{lineTotal})');
      expect(a.toString(), allOf(contains('orderTotal'), contains('SUM')));
    });
  });
}
