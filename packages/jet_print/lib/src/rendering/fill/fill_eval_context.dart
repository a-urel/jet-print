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
  /// Creates a context. [warnedFields] and [pageRefs] are shared sinks the caller
  /// owns; [elementId] tags any warning with its originating element.
  FillEvalContext({
    this.row,
    this.params = const <String, Object?>{},
    this.variables = const <String, JetValue>{},
    required this.functions,
    required this.diagnostics,
    required this.warnedFields,
    required this.pageRefs,
    this.elementId,
  });

  /// The current row (null for title/summary/noData).
  final DataRow? row;

  /// The parameter map.
  final Map<String, Object?> params;

  /// The calculator's current variable values.
  final Map<String, JetValue> variables;

  @override
  final JetFunctionRegistry functions;

  /// The diagnostics sink.
  final ReportDiagnostics diagnostics;

  /// Field names already warned about (dedup, shared across one fill).
  final Set<String> warnedFields;

  /// Reserved page-scoped names referenced during evaluation (shared sink).
  final Set<String> pageRefs;

  /// The element being resolved, for warning attribution (null for var/group).
  final String? elementId;

  @override
  JetValue resolveField(String name) {
    final DataRow? r = row;
    if (r == null) return const JetNull();
    if (!r.hasField(name)) {
      if (warnedFields.add(name)) {
        diagnostics.warning('Field "$name" is not in the data schema',
            elementId: elementId);
      }
      return const JetNull();
    }
    return JetValue.from(r.field(name));
  }

  @override
  JetValue resolveParam(String name) => params.containsKey(name)
      ? JetValue.from(params[name])
      : const JetNull();

  @override
  JetValue resolveVariable(String name) {
    if (kPageScopedVariables.contains(name)) {
      pageRefs.add(name);
      return const JetNull();
    }
    return variables[name] ?? const JetNull();
  }
}
