/// Built-in string functions for the expression engine (spec 005a).
library;

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `UPPER`, `LOWER`, `TRIM`, `LENGTH`, `CONCAT`, `SUBSTRING`.
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
    _stringUnary(a, 'UPPER', (String s) => s.toUpperCase());

JetValue _lower(List<JetValue> a, EvalContext c) =>
    _stringUnary(a, 'LOWER', (String s) => s.toLowerCase());

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
