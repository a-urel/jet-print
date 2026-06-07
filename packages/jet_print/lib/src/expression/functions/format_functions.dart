/// Built-in FORMAT function for the expression engine (spec 005a).
library;

import 'package:intl/intl.dart';

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `FORMAT(value, pattern)`.
///
/// Formats a [JetNumber] via [NumberFormat] or a [JetDate] via [DateFormat]
/// using the ICU [pattern] string. Returns a [JetError] for a missing/invalid
/// pattern, an unsupported value type, or an unparseable pattern.
///
/// Locale: grouping/decimal symbols follow the ambient `Intl.defaultLocale`
/// (which falls back to `en_US` when unset), so the same pattern can render
/// `1,234.50` or `1.234,50` depending on the host. A per-report locale injected
/// through the evaluation context is a planned enhancement (005b/later).
void registerFormatFunctions(JetFunctionRegistry registry) {
  registry.register('FORMAT', _format);
}

JetValue _format(List<JetValue> args, EvalContext ctx) {
  if (args.length != 2) return const JetError('FORMAT expects 2 arguments');
  final JetValue value = args[0];
  final JetValue pattern = args[1];
  if (pattern is! JetString) {
    return const JetError('FORMAT pattern must be a string');
  }
  try {
    return switch (value) {
      JetNumber(value: final double v) =>
        JetString(NumberFormat(pattern.value).format(v)),
      JetDate(value: final DateTime v) =>
        JetString(DateFormat(pattern.value).format(v)),
      _ => const JetError('FORMAT expects a number or date as its first '
          'argument'),
    };
  } on FormatException catch (e) {
    return JetError('FORMAT failed: ${e.message}');
  }
}
