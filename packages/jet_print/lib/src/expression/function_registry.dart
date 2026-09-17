/// The expression function registry — the evaluator's name→function table.
///
/// **Internal seam, not a host extension point.** [JetFunctionRegistry] is not
/// exported from `lib/jet_print.dart`, and no public entry point accepts one:
/// `JetReportEngine.renderDefinition` takes no registry and `RenderOptions` has
/// no field for one, so `ReportFiller`/`ReportLayouter` always build their own
/// from `registerBuiltInFunctions`. A host therefore cannot register a custom
/// function today. Opening this up is a public-API change — export the class
/// *and* thread a host registry through `RenderOptions` into both the filler and
/// the layouter — not a wording change here.
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
/// The library's own registration seam: `registerBuiltInFunctions` and the
/// per-family `register*Functions` helpers fill one at fill/layout setup.
/// Built-in names are UPPERCASE by convention and lookup is case-sensitive.
/// It is not reachable from outside the package — see the library dartdoc.
class JetFunctionRegistry {
  final Map<String, JetExprFn> _functions = <String, JetExprFn>{};

  /// Registers [fn] under [name], replacing any existing entry.
  void register(String name, JetExprFn fn) => _functions[name] = fn;

  /// Returns the function registered under [name], or `null` if none.
  JetExprFn? lookup(String name) => _functions[name];
}
