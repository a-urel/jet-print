// VariableAccumulator: per-calculation folding (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/variable_accumulator.dart';
import 'package:jet_print/src/expression/value.dart';

VariableAccumulator _acc(JetCalculation c) => VariableAccumulator(c);

void main() {
  test('none holds the latest value (including null/error passthrough)', () {
    final VariableAccumulator a = _acc(JetCalculation.none);
    expect(a.value, const JetNull());
    a.fold(const JetNumber(5));
    expect(a.value, const JetNumber(5));
    a.fold(const JetNull());
    expect(a.value, const JetNull());
  });

  test('sum adds numbers and skips null/error/wrong-type', () {
    final VariableAccumulator a = _acc(JetCalculation.sum);
    expect(a.value, const JetNumber(0));
    a.fold(const JetNumber(2));
    a.fold(const JetNull()); // skipped
    a.fold(const JetError('x')); // skipped
    a.fold(const JetString('y')); // skipped (wrong type)
    a.fold(const JetNumber(3));
    expect(a.value, const JetNumber(5));
  });

  test('count counts non-null/non-error values of any type', () {
    final VariableAccumulator a = _acc(JetCalculation.count);
    a.fold(const JetNumber(1));
    a.fold(const JetString('x'));
    a.fold(const JetNull()); // skipped
    a.fold(const JetError('e')); // skipped
    expect(a.value, const JetNumber(2));
  });

  test('average is sum/count, null while empty', () {
    final VariableAccumulator a = _acc(JetCalculation.average);
    expect(a.value, const JetNull());
    a.fold(const JetNumber(2));
    a.fold(const JetNumber(4));
    expect(a.value, const JetNumber(3));
  });

  test('min/max keep the extreme', () {
    final VariableAccumulator lo = _acc(JetCalculation.min);
    final VariableAccumulator hi = _acc(JetCalculation.max);
    for (final JetValue v in <JetValue>[
      const JetNumber(3),
      const JetNumber(1),
      const JetNumber(2),
    ]) {
      lo.fold(v);
      hi.fold(v);
    }
    expect(lo.value, const JetNumber(1));
    expect(hi.value, const JetNumber(3));
  });

  test('first/last pick endpoints, skipping null', () {
    final VariableAccumulator f = _acc(JetCalculation.first);
    final VariableAccumulator l = _acc(JetCalculation.last);
    for (final JetValue v in <JetValue>[
      const JetNull(),
      const JetString('a'),
      const JetString('b'),
    ]) {
      f.fold(v);
      l.fold(v);
    }
    expect(f.value, const JetString('a'));
    expect(l.value, const JetString('b'));
  });

  test('reset returns to the seed', () {
    final VariableAccumulator a = _acc(JetCalculation.sum);
    a.fold(const JetNumber(9));
    a.reset();
    expect(a.value, const JetNumber(0));
  });

  test('skippedNonNumeric counts wrong-type SUM inputs, not null/error', () {
    final VariableAccumulator a = _acc(JetCalculation.sum);
    a.fold(const JetNumber(2));
    a.fold(const JetNull()); // legit blank — NOT a skip
    a.fold(const JetError('x')); // error — NOT a skip
    a.fold(const JetString('y')); // wrong type — a skip
    a.fold(const JetNumber(3));
    expect(a.value, const JetNumber(5));
    expect(a.skippedNonNumeric, 1);
  });

  test('skippedNonNumeric counts wrong-type AVG inputs', () {
    final VariableAccumulator a = _acc(JetCalculation.average);
    a.fold(const JetNumber(4));
    a.fold(const JetString('nope')); // skip
    a.fold(const JetNumber(6));
    expect(a.value, const JetNumber(5)); // (4+6)/2
    expect(a.skippedNonNumeric, 1);
  });

  test('skippedNonNumeric counts incomparable MIN/MAX inputs (after first)',
      () {
    final VariableAccumulator a = _acc(JetCalculation.min);
    a.fold(const JetNumber(5)); // first value taken unconditionally
    a.fold(const JetString('x')); // incomparable to a number -> skip
    a.fold(const JetNumber(2));
    expect(a.value, const JetNumber(2));
    expect(a.skippedNonNumeric, 1);
  });

  test('count never skips; it accepts any non-null/non-error type', () {
    final VariableAccumulator a = _acc(JetCalculation.count);
    a.fold(const JetString('a'));
    a.fold(const JetNumber(1));
    expect(a.skippedNonNumeric, 0);
  });

  test('reset() does NOT clear skippedNonNumeric (lifetime-monotonic)', () {
    final VariableAccumulator a = _acc(JetCalculation.sum);
    a.fold(const JetString('y')); // skip
    expect(a.skippedNonNumeric, 1);
    a.reset();
    expect(a.value, const JetNumber(0), reason: 'value state resets');
    expect(a.skippedNonNumeric, 1, reason: 'skip count is lifetime-monotonic');
  });
}
