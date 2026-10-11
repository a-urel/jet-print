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
        JetString(_formatNumber(NumberFormat(pattern), v)),
      JetDate(value: final DateTime v) =>
        JetString(DateFormat(pattern).format(v)),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// Formats [v] with [format], printing a value whose magnitude formats as
/// zero as zero itself. Numbers are doubles, so a total that should foot to
/// zero can land a hair below it, and intl signs anything below zero (`-0,00`,
/// or the negative subpattern's `(0,00)`); zero has no sign (#95). Comparing
/// formatted text, not digits, leaves the rounding and the locale's digits to
/// intl.
String _formatNumber(NumberFormat format, double v) {
  if (v.isNegative) {
    final String zero = format.format(0);
    if (format.format(-v) == zero) return zero;
  }
  return format.format(v);
}

/// Applies the label `format` property semantics: an empty
/// [pattern], a type the pattern does not fit, or a malformed pattern all leave
/// [value] unchanged (never an error token); a number/date with a valid pattern
/// becomes the formatted [JetString].
///
/// One coercion is specific to the property (not [tryJetFormat]/`FORMAT`): when
/// the pattern is a **date** pattern and the value is a string that parses as an
/// ISO date, it is formatted as a date. This lets a field declared `dateTime`
/// but supplied as an ISO string (common with JSON data) still honor a date
/// format — a non-date string is left unchanged, so nothing else is affected.
JetValue applyJetFormat(JetValue value, String pattern) {
  if (pattern.isEmpty) return value;
  return tryJetFormat(_coerceForFormat(value, pattern), pattern) ?? value;
}

/// Any ICU date-field letter — the signal that a pattern is a date pattern (the
/// number presets/patterns use only `# 0 , . ¤ % E`, none of these letters).
final RegExp _datePatternLetter =
    RegExp('[GyYuUrQqMLwWdDFgEecabBhHKkmsSAzZOvVXx]');

/// For the property's date-string convenience: a string value under a date
/// pattern that parses as an ISO date becomes a [JetDate]; everything else is
/// returned untouched (so number patterns and non-date strings are unaffected).
JetValue _coerceForFormat(JetValue value, String pattern) {
  if (value is JetString && _datePatternLetter.hasMatch(pattern)) {
    final DateTime? parsed = DateTime.tryParse(value.value.trim());
    if (parsed != null) return JetDate(parsed);
  }
  return value;
}
