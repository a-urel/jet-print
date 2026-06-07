/// Built-in logic functions for the expression engine (spec 005a).
library;

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `IF`, `COALESCE`, `ISNULL`.
///
/// `IF(cond, a, b)` evaluates *all* arguments (functions receive pre-evaluated
/// values); use the `?:` operator when short-circuit evaluation is required.
void registerLogicFunctions(JetFunctionRegistry registry) {
  registry
    ..register('IF', _if)
    ..register('COALESCE', _coalesce)
    ..register('ISNULL', _isNull);
}

JetValue _if(List<JetValue> args, EvalContext c) {
  if (args.length != 3) return const JetError('IF expects 3 arguments');
  final JetValue cond = args[0];
  return switch (cond) {
    JetBool(value: final bool b) => b ? args[1] : args[2],
    _ => const JetError('IF condition must be boolean'),
  };
}

JetValue _coalesce(List<JetValue> args, EvalContext c) {
  for (final JetValue v in args) {
    if (v is! JetNull) return v;
  }
  return const JetNull();
}

JetValue _isNull(List<JetValue> args, EvalContext c) {
  if (args.length != 1) return const JetError('ISNULL expects 1 argument');
  return JetBool(args[0] is JetNull);
}
