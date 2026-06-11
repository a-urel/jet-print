/// Shared value formatting (013) — the one place number/date patterns are
/// applied, so the `FORMAT` expression function and the label `format` property
/// can never drift.
///
/// Locale: grouping/decimal symbols and date names follow
/// `Intl.getCurrentLocale()`, exactly as `FORMAT` does. At render time the
/// engine scopes the pass with the explicit per-render locale, keeping output
/// deterministic.
library;

import 'package:intl/intl.dart';

import '../value.dart';

/// Formats [value] with the ICU [pattern], or returns null when [value] is not
/// a number/date or the pattern is malformed. This is the shared formatting
/// core; callers decide what to do with a null (the property falls back to the
/// unformatted value; `FORMAT` raises a [JetError]).
JetString? tryJetFormat(JetValue value, String pattern) {
  try {
    return switch (value) {
      JetNumber(value: final double v) =>
        JetString(NumberFormat(pattern).format(v)),
      JetDate(value: final DateTime v) =>
        JetString(DateFormat(pattern).format(v)),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// Applies the label `format` property semantics (013 / FR-010–FR-012): an empty
/// [pattern], a type the pattern does not fit, or a malformed pattern all leave
/// [value] unchanged (never an error token); a number/date with a valid pattern
/// becomes the formatted [JetString].
JetValue applyJetFormat(JetValue value, String pattern) {
  if (pattern.isEmpty) return value;
  return tryJetFormat(value, pattern) ?? value;
}
