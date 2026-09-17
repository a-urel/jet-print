/// The Fill-stage [EvalContext]. Wraps a data row, params, and the
/// calculator's variable values, and records two content signals: a
/// missing-field **warning** (a `$F{}` to a name the row's schema does not
/// declare) and a reserved **page-scoped** variable reference (into
/// [pageRefs], for the caller to reject, §2/§5).
///
/// The missing-field warning goes to the [DiagnosticBudget] when one is
/// supplied — row-tagged, deduped within the row, and capped — which is every
/// real fill. The [warnedFields] once-only sink is the budget-less fallback and
/// no production path reaches it; see `diagnostic_budget.dart`.
library;

import '../../data/data_row.dart';
import '../../expression/eval_context.dart';
import '../../expression/function_registry.dart';
import '../../expression/value.dart';
import 'diagnostic_budget.dart';
import 'page_variables.dart';
import 'report_diagnostics.dart';

/// An [EvalContext] that records Fill diagnostics as a side effect of resolution.
class FillEvalContext implements EvalContext {
  /// Creates a context over an optional [row], [params], and [variables].
  ///
  /// [warnedFields] and [pageRefs] are shared sinks the caller owns and reads
  /// back after the fill. Resolving a reserved page-scoped variable adds its
  /// name to [pageRefs]. Resolving a missing field records through [budget] when
  /// one is passed, and only otherwise adds the name to [warnedFields] to dedupe
  /// a single warning. Both mutations happen as a side effect of [resolveField]
  /// and [resolveVariable] respectively. [elementId] tags the missing-field
  /// warning with its originating element on either path.
  FillEvalContext({
    DataRow? row,
    Map<String, Object?> params = const <String, Object?>{},
    Map<String, JetValue> variables = const <String, JetValue>{},
    required JetFunctionRegistry functions,
    required ReportDiagnostics diagnostics,
    required Set<String> warnedFields,
    required Set<String> pageRefs,
    String? elementId,
    DiagnosticBudget? budget,
  })  : _row = row,
        _params = params,
        _variables = variables,
        _functions = functions,
        _diagnostics = diagnostics,
        _warnedFields = warnedFields,
        _pageRefs = pageRefs,
        _elementId = elementId,
        _budget = budget;

  final DataRow? _row;
  final Map<String, Object?> _params;
  final Map<String, JetValue> _variables;
  final JetFunctionRegistry _functions;
  final ReportDiagnostics _diagnostics;
  final Set<String> _warnedFields;
  final Set<String> _pageRefs;
  final String? _elementId;
  final DiagnosticBudget? _budget;

  @override
  JetFunctionRegistry get functions => _functions;

  @override
  JetValue resolveField(String name) {
    final DataRow? row = _row;
    if (row == null) return const JetNull();
    if (!row.hasField(name)) {
      final DiagnosticBudget? budget = _budget;
      if (budget != null) {
        budget.recordRowIssue(
            'field:$name', 'Field "$name" is not in the data schema',
            elementId: _elementId);
      } else if (_warnedFields.add(name)) {
        _diagnostics.warning('Field "$name" is not in the data schema',
            elementId: _elementId);
      }
      return const JetNull();
    }
    return JetValue.from(row.field(name));
  }

  @override
  JetValue resolveParam(String name) => _params.containsKey(name)
      ? JetValue.from(_params[name])
      : const JetNull();

  @override
  JetValue resolveVariable(String name) {
    if (kPageScopedVariables.contains(name)) {
      _pageRefs.add(name);
      return const JetNull();
    }
    return _variables[name] ?? const JetNull();
  }
}
