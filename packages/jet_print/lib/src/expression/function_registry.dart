/// The expression function registry — engine extension point #4 (spec 005a).
library;

import 'eval_context.dart';
import 'value.dart';

/// A callable expression function: receives already-evaluated [args] and the
/// [context], and returns a [JetValue].
///
/// The evaluator auto-propagates a [JetError] argument before calling a
/// function, so implementations only ever see non-error [args] — they validate
/// arity and types and return a [JetError] on a violation.
typedef JetExprFn = JetValue Function(List<JetValue> args, EvalContext context);

/// A mutable name→function table consulted by the evaluator for call nodes.
///
/// This is the public extension point: consumers `register` custom functions
/// with zero core edits. Built-in names are UPPERCASE by convention and lookup
/// is case-sensitive.
class JetFunctionRegistry {
  final Map<String, JetExprFn> _functions = <String, JetExprFn>{};

  /// Registers [fn] under [name], replacing any existing entry.
  void register(String name, JetExprFn fn) => _functions[name] = fn;

  /// Returns the function registered under [name], or `null` if none.
  JetExprFn? lookup(String name) => _functions[name];
}
