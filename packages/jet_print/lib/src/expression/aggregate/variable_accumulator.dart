/// Per-calculation accumulator for a report variable (spec 005b). Internal to
/// the expression seam.
library;

import '../../domain/report_variable.dart';
import '../value.dart';

/// Folds per-row [JetValue]s into a single value per a [JetCalculation].
///
/// Contribution filter: `JetNull`, `JetError`, and wrong-typed values are
/// skipped (the running value is unaffected) — except [JetCalculation.none],
/// which passes its latest value through unchanged.
class VariableAccumulator {
  /// Creates an accumulator for [calculation], seeded to its initial value.
  VariableAccumulator(this.calculation) {
    reset();
  }

  /// The fold strategy.
  final JetCalculation calculation;

  double _sum = 0;
  int _count = 0;
  JetValue _value = const JetNull();
  bool _hasValue = false;

  /// The accumulator's current value.
  JetValue get value => switch (calculation) {
        JetCalculation.none => _value,
        JetCalculation.sum => JetNumber(_sum),
        JetCalculation.count => JetNumber(_count.toDouble()),
        JetCalculation.average =>
          _count == 0 ? const JetNull() : JetNumber(_sum / _count),
        JetCalculation.min ||
        JetCalculation.max ||
        JetCalculation.first ||
        JetCalculation.last =>
          _hasValue ? _value : const JetNull(),
      };

  /// Folds one per-row [input] into the accumulator.
  void fold(JetValue input) {
    if (calculation == JetCalculation.none) {
      _value = input;
      return;
    }
    if (input is JetNull || input is JetError) return; // skip blanks/errors
    switch (calculation) {
      case JetCalculation.sum:
        if (input is JetNumber) _sum += input.value;
      case JetCalculation.average:
        if (input is JetNumber) {
          _sum += input.value;
          _count++;
        }
      case JetCalculation.count:
        _count++;
      case JetCalculation.min:
        if (!_hasValue) {
          _value = input;
          _hasValue = true;
        } else {
          final int? c = jetCompare(input, _value);
          if (c != null && c < 0) _value = input;
        }
      case JetCalculation.max:
        if (!_hasValue) {
          _value = input;
          _hasValue = true;
        } else {
          final int? c = jetCompare(input, _value);
          if (c != null && c > 0) _value = input;
        }
      case JetCalculation.first:
        if (!_hasValue) {
          _value = input;
          _hasValue = true;
        }
      case JetCalculation.last:
        _value = input;
        _hasValue = true;
      case JetCalculation.none:
        break; // handled above
    }
  }

  /// Re-seeds the accumulator to its initial (empty-scope) state.
  void reset() {
    _sum = 0;
    _count = 0;
    _value = const JetNull();
    _hasValue = false;
  }
}
