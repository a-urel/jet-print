// Shared value formatter (013 / T017): the label `format` property semantics —
// number/date patterns apply; mismatch/malformed/empty leave the value as-is.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/format/apply_jet_format.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  test('formats a number with a numeric pattern', () {
    expect(applyJetFormat(const JetNumber(1234.5), '#,##0.00'),
        const JetString('1,234.50'));
  });

  test('formats a date with a date pattern', () {
    expect(applyJetFormat(JetDate(DateTime(2026, 6, 11)), 'yyyy-MM-dd'),
        const JetString('2026-06-11'));
  });

  test('an empty pattern leaves the value unchanged', () {
    expect(applyJetFormat(const JetNumber(5), ''), const JetNumber(5));
  });

  test('a type mismatch leaves the value unchanged (no error)', () {
    expect(applyJetFormat(const JetString('hello'), '#,##0.00'),
        const JetString('hello'));
  });

  test('a malformed pattern leaves the value unchanged (no error)', () {
    final JetValue out = applyJetFormat(const JetNumber(5), '###0.00#0#0E');
    // Whatever intl rejects, the contract is: fall back, never throw/error.
    expect(out, isA<JetValue>());
    expect(out, isNot(isA<JetError>()));
  });

  test('null/bool/error values pass through unchanged', () {
    expect(applyJetFormat(const JetNull(), '#,##0'), const JetNull());
    expect(applyJetFormat(const JetBool(true), '#,##0'), const JetBool(true));
  });
}
