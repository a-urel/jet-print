/// Shared value formatting (013) — the one place number/date patterns are
/// applied, so the `FORMAT` expression function and the label `format` property
/// can never drift.
///
/// Locale: grouping/decimal symbols and date names follow
/// `Intl.getCurrentLocale()`, exactly as `FORMAT` does. At render time the
/// engine scopes the pass with the explicit per-render locale, keeping output
/// deterministic. What `¤` prints is scoped the same way, by
/// [runWithCurrencySymbol].
library;

import 'dart:async';

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
        JetString(_formatNumber(_numberFormat(pattern), v)),
      JetDate(value: final DateTime v) =>
        JetString(DateFormat(pattern).format(v)),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// The zone key [runWithCurrencySymbol] binds; private, so only it can.
final Object _currencySymbolKey = Object();

/// Runs [body] with [symbol] as what `¤` prints in number patterns, or, when
/// [symbol] is null, with `¤` printing the locale's ISO 4217 code as it always
/// has. Scoped like `Intl.withLocale`, which the engine wraps it beside, so a
/// page built after the render returns is re-entered with the same symbol.
T runWithCurrencySymbol<T>(String? symbol, T Function() body) => symbol == null
    ? body()
    : runZoned(body, zoneValues: <Object, Object>{_currencySymbolKey: symbol});

/// The [NumberFormat] for [pattern], printing the scoped currency symbol for
/// `¤` when one is bound.
///
/// intl's currency constructor also replaces the pattern's fraction digits
/// with the currency's own (two for the lira), so a `#,##0 ¤` would print
/// `1.234,50 ₺`. The pattern's digits are put back from a plain parse of the
/// same pattern: only the sign may change.
NumberFormat _numberFormat(String pattern) {
  final NumberFormat plain = NumberFormat(pattern);
  final Object? symbol = Zone.current[_currencySymbolKey];
  if (symbol is! String || !pattern.contains('¤')) return plain;
  return NumberFormat.currency(symbol: symbol, customPattern: pattern)
    ..minimumFractionDigits = plain.minimumFractionDigits
    ..maximumFractionDigits = plain.maximumFractionDigits;
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
