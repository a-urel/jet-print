// Web-platform fidelity: jetStringify must reproduce VM (Dart-native)
// double.toString() output on web (JS), where integer-valued doubles lose the
// trailing `.0` because JS's Number.toString() omits it.
//
// This test is browser-only; the same assertion already holds on the VM by
// default. It is listed here so the Chrome leg of CI can catch regressions.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  group('jetStringify — web fidelity', () {
    test('integer-valued double renders with trailing .0 (5.0 not 5)', () {
      expect(jetStringify(const JetNumber(5.0)), '5.0');
    });

    test('integer-valued double renders with trailing .0 (100.0 not 100)', () {
      expect(jetStringify(const JetNumber(100.0)), '100.0');
    });

    test('integer-valued zero renders as 0.0', () {
      expect(jetStringify(const JetNumber(0.0)), '0.0');
    });

    test('negative integer-valued double renders with trailing .0 (-3.0)', () {
      expect(jetStringify(const JetNumber(-3.0)), '-3.0');
    });

    test('non-integer double passes through unchanged (3.14)', () {
      expect(jetStringify(const JetNumber(3.14)), '3.14');
    });

    test('very large integer-valued double (1e21) uses scientific notation',
        () {
      // 1e21 is the scientific-notation threshold; both platforms agree here.
      expect(jetStringify(const JetNumber(1e21)), '1e+21');
    });

    test('infinity is not affected', () {
      expect(
        jetStringify(const JetNumber(double.infinity)),
        'Infinity',
      );
    });

    test('NaN is not affected', () {
      expect(
        jetStringify(const JetNumber(double.nan)),
        'NaN',
      );
    });
  });
}
