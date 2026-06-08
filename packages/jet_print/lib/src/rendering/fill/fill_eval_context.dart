/// The Fill-stage [EvalContext] (spec 007b). Wraps a data row, params, and the
/// calculator's variable values, and records two content signals into shared
/// sinks: a missing-field **warning** (a `$F{}` to a name the row's schema does
/// not declare; deduped via [warnedFields]) and a reserved **page-scoped**
/// variable reference (into [pageRefs], for the caller to reject, §2/§5).
library;

import '../../data/data_row.dart';
import '../../expression/eval_context.dart';
import '../../expression/function_registry.dart';
import '../../expression/value.dart';
import 'page_variables.dart';
import 'report_diagnostics.dart';

/// An [EvalContext] that records Fill diagnostics as a side effect of resolution.
class FillEvalContext implements EvalContext {
  /// Creates a context over an optional [row], [params], and [variables].
  ///
  /// [warnedFields] and [pageRefs] are shared sinks the caller owns and reads
  /// back after the fill: resolving a missing field adds its name to
  /// [warnedFields] (deduping the warning), and resolving a reserved page-scoped
  /// variable adds its name to [pageRefs]. Both mutations happen as a side effect
  /// of [resolveField] and [resolveVariable] respectively. [elementId] tags any
  /// missing-field warning with its originating element.
  FillEvalContext({
    DataRow? row,
    Map<String, Object?> params = const <String, Object?>{},
    Map<String, JetValue> variables = const <String, JetValue>{},
    required JetFunctionRegistry functions,
    required ReportDiagnostics diagnostics,
    required Set<String> warnedFields,
    required Set<String> pageRefs,
    String? elementId,
  })  : _row = row,
        _params = params,
        _variables = variables,
        _functions = functions,
        _diagnostics = diagnostics,
        _warnedFields = warnedFields,
        _pageRefs = pageRefs,
        _elementId = elementId;

  final DataRow? _row;
  final Map<String, Object?> _params;
  final Map<String, JetValue> _variables;
  final JetFunctionRegistry _functions;
  final ReportDiagnostics _diagnostics;
  final Set<String> _warnedFields;
  final Set<String> _pageRefs;
  final String? _elementId;

  @override
  JetFunctionRegistry get functions => _functions;

  @override
  JetValue resolveField(String name) {
    final DataRow? row = _row;
    if (row == null) return const JetNull();
    if (!row.hasField(name)) {
      if (_warnedFields.add(name)) {
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
