/// Built-in math functions for the expression engine (spec 005a).
library;

import 'dart:math' as math;

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `ABS`, `ROUND`, `CEIL`, `FLOOR`, `MIN`, `MAX` into [registry].
void registerMathFunctions(JetFunctionRegistry registry) {
  registry
    ..register('ABS', _abs)
    ..register('ROUND', _round)
    ..register('CEIL', _ceil)
    ..register('FLOOR', _floor)
    ..register('MIN', _min)
    ..register('MAX', _max);
}

double? _num(JetValue v) => v is JetNumber ? v.value : null;

JetValue _abs(List<JetValue> args, EvalContext ctx) {
  if (args.length != 1) return const JetError('ABS expects 1 argument');
  final double? x = _num(args[0]);
  return x == null
      ? const JetError('ABS expects a number')
      : JetNumber(x.abs());
}

JetValue _round(List<JetValue> args, EvalContext ctx) {
  if (args.isEmpty || args.length > 2) {
    return const JetError('ROUND expects 1 or 2 arguments');
  }
  final double? x = _num(args[0]);
  if (x == null) return const JetError('ROUND expects a number');
  int digits = 0;
  if (args.length == 2) {
    final double? d = _num(args[1]);
    if (d == null) return const JetError('ROUND digits must be a number');
    digits = d.toInt();
  }
  final num factor = math.pow(10, digits);
  return JetNumber((x * factor).roundToDouble() / factor);
}

JetValue _ceil(List<JetValue> args, EvalContext ctx) {
  if (args.length != 1) return const JetError('CEIL expects 1 argument');
  final double? x = _num(args[0]);
  return x == null
      ? const JetError('CEIL expects a number')
      : JetNumber(x.ceilToDouble());
}

JetValue _floor(List<JetValue> args, EvalContext ctx) {
  if (args.length != 1) return const JetError('FLOOR expects 1 argument');
  final double? x = _num(args[0]);
  return x == null
      ? const JetError('FLOOR expects a number')
      : JetNumber(x.floorToDouble());
}

JetValue _min(List<JetValue> args, EvalContext ctx) =>
    _reduce(args, 'MIN', (double a, double b) => math.min(a, b));

JetValue _max(List<JetValue> args, EvalContext ctx) =>
    _reduce(args, 'MAX', (double a, double b) => math.max(a, b));

JetValue _reduce(
    List<JetValue> args, String name, double Function(double, double) f) {
  if (args.isEmpty) return JetError('$name expects at least 1 argument');
  double acc;
  final double? first = _num(args[0]);
  if (first == null) return JetError('$name expects numbers');
  acc = first;
  for (int i = 1; i < args.length; i++) {
    final double? x = _num(args[i]);
    if (x == null) return JetError('$name expects numbers');
    acc = f(acc, x);
  }
  return JetNumber(acc);
}
