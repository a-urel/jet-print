/// The page-scoped [EvalContext] (spec 008c): resolves `PAGE_NUMBER`/`PAGE_COUNT`
/// and report `$P{}` parameters for page-chrome text substitution. Pure value
/// resolution — diagnostics are surfaced by the layouter's static pre-pass.
library;

import '../../expression/eval_context.dart';
import '../../expression/function_registry.dart';
import '../../expression/value.dart';

/// An [EvalContext] over a single page's number/count and the report params.
class PageEvalContext implements EvalContext {
  /// Creates a context for page [pageNumber] of [pageCount], with the
  /// already-normalized [params] (e.g. `FilledReport.params`) and the [functions]
  /// registry. Unlike the row-scoped contexts, params are pre-lifted to [JetValue]
  /// at the IR boundary (008c), so this resolver does no per-lookup conversion.
  PageEvalContext({
    required int pageNumber,
    required int pageCount,
    required Map<String, JetValue> params,
    required JetFunctionRegistry functions,
  })  : _pageNumber = pageNumber,
        _pageCount = pageCount,
        _params = params,
        _functions = functions;

  final int _pageNumber;
  final int _pageCount;
  final Map<String, JetValue> _params;
  final JetFunctionRegistry _functions;

  @override
  JetFunctionRegistry get functions => _functions;

  @override
  JetValue resolveField(String name) => const JetNull();

  @override
  JetValue resolveParam(String name) => _params[name] ?? const JetNull();

  @override
  JetValue resolveVariable(String name) {
    // The two page-scoped variable names (kPageScopedVariables, spec 007b §2).
    // Resolved as strings: the engine is all-double, so a JetNumber would render
    // "1.0", and `+` will not concatenate a string literal with a number (008c §4).
    if (name == 'PAGE_NUMBER') return JetString('$_pageNumber');
    if (name == 'PAGE_COUNT') return JetString('$_pageCount');
    return const JetNull();
  }
}
