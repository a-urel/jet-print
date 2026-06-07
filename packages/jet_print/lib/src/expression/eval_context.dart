/// The expression evaluation environment (spec 005a).
library;

import '../data/data_row.dart';
import 'function_registry.dart';
import 'value.dart';

/// Resolves references and exposes functions during evaluation.
///
/// A reference that cannot be resolved (a missing field or parameter) returns
/// [JetNull] rather than an error — the render stage treats a null field as
/// blank with a warning (§7), not a hard failure.
abstract class EvalContext {
  /// Resolves a `$F{name}` field reference.
  JetValue resolveField(String name);

  /// Resolves a `$P{name}` parameter reference.
  JetValue resolveParam(String name);

  /// The function registry consulted for call nodes.
  JetFunctionRegistry get functions;
}

/// The default [EvalContext]: fields from a [DataRow], params from a map.
///
/// This is the bridge from the expression seam to the data seam. A field that
/// the row does not declare (or whose value is null) resolves to [JetNull];
/// other values are lifted via [JetValue.from].
class RowEvalContext implements EvalContext {
  /// Creates a context over an optional [row] and [params].
  RowEvalContext({
    DataRow? row,
    Map<String, Object?> params = const <String, Object?>{},
    required JetFunctionRegistry functions,
  })  : _row = row,
        _params = params,
        _functions = functions;

  final DataRow? _row;
  final Map<String, Object?> _params;
  final JetFunctionRegistry _functions;

  @override
  JetFunctionRegistry get functions => _functions;

  @override
  JetValue resolveField(String name) {
    final DataRow? row = _row;
    if (row == null || !row.hasField(name)) return const JetNull();
    return JetValue.from(row.field(name));
  }

  @override
  JetValue resolveParam(String name) => _params.containsKey(name)
      ? JetValue.from(_params[name])
      : const JetNull();
}
