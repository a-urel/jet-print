/// Built-in string functions for the expression engine.
library;

import 'package:intl/intl.dart';

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `UPPER`, `LOWER`, `TRIM`, `LENGTH`, `CONCAT`, `SUBSTRING`.
///
/// `UPPER` and `LOWER` case by `Intl.getCurrentLocale()`, which the
/// JetReportEngine scopes to `RenderOptions.locale` for every fill/layout pass,
/// exactly as it does for `FORMAT`. Turkish and Azerbaijani map `i`↔`İ` and
/// `ı`↔`I`; every other locale takes Dart's default mapping.
void registerStringFunctions(JetFunctionRegistry registry) {
  registry
    ..register('UPPER', _upper)
    ..register('LOWER', _lower)
    ..register('TRIM', _trim)
    ..register('LENGTH', _length)
    ..register('CONCAT', _concat)
    ..register('SUBSTRING', _substring);
}

JetValue _stringUnary(
    List<JetValue> args, String name, String Function(String) f) {
  if (args.length != 1) return JetError('$name expects 1 argument');
  final JetValue v = args[0];
  return v is JetString
      ? JetString(f(v.value))
      : JetError('$name expects a string');
}

JetValue _upper(List<JetValue> a, EvalContext c) =>
    _stringUnary(a, 'UPPER', (String s) {
      // Dart's mapping takes `i` to `I`; in Turkic the dotted `i` keeps its
      // dot. `ı` already uppercases to `I`, and `İ` stays `İ`.
      return (_isTurkic() ? s.replaceAll('i', 'İ') : s).toUpperCase();
    });

JetValue _lower(List<JetValue> a, EvalContext c) =>
    _stringUnary(a, 'LOWER', (String s) {
      // Dart's mapping takes `I` to `i`, and `İ` to `i` on the VM but to `i`
      // plus a combining dot on the web; in Turkic they are `ı` and `i`.
      return (_isTurkic() ? s.replaceAll('İ', 'i').replaceAll('I', 'ı') : s)
          .toLowerCase();
    });

/// Whether the current Intl locale cases the Turkic `i`: `tr` or `az`, with or
/// without a region (`tr_TR`, `az-Latn`).
bool _isTurkic() {
  final String language =
      Intl.getCurrentLocale().split(RegExp('[_-]')).first.toLowerCase();
  return language == 'tr' || language == 'az';
}

JetValue _trim(List<JetValue> a, EvalContext c) =>
    _stringUnary(a, 'TRIM', (String s) => s.trim());

JetValue _length(List<JetValue> args, EvalContext c) {
  if (args.length != 1) return const JetError('LENGTH expects 1 argument');
  final JetValue v = args[0];
  return v is JetString
      ? JetNumber(v.value.length.toDouble())
      : const JetError('LENGTH expects a string');
}

JetValue _concat(List<JetValue> args, EvalContext c) =>
    JetString(args.map(jetStringify).join());

JetValue _substring(List<JetValue> args, EvalContext c) {
  if (args.length < 2 || args.length > 3) {
    return const JetError('SUBSTRING expects 2 or 3 arguments');
  }
  final JetValue s = args[0];
  final JetValue start = args[1];
  if (s is! JetString) return const JetError('SUBSTRING expects a string');
  if (start is! JetNumber) {
    return const JetError('SUBSTRING start must be a number');
  }
  final int len = s.value.length;
  final int from = start.value.toInt().clamp(0, len);
  int to = len;
  if (args.length == 3) {
    final JetValue length = args[2];
    if (length is! JetNumber) {
      return const JetError('SUBSTRING length must be a number');
    }
    to = (from + length.value.toInt()).clamp(from, len);
  }
  return JetString(s.value.substring(from, to));
}
