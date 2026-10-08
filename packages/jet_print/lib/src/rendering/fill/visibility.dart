/// Fill-time evaluation of an object's [BoolProperty] visibility (elements and
/// bands share this). Fail-safe: any parse error, evaluation error, page-scoped
/// variable use, or non-boolean result keeps the object VISIBLE and records a
/// diagnostic, so a broken expression never silently drops content.
library;

import '../../domain/bool_property.dart';
import '../../expression/eval_context.dart';
import '../../expression/expression.dart';
import '../../expression/expression_exception.dart';
import '../../expression/value.dart';
import 'report_diagnostics.dart';

/// Returns whether the object is visible, evaluating [prop] against [ctx].
///
/// A row-scoped `FillEvalContext` fills [pageRefs] when a page-scoped variable
/// is referenced — illegal for a body object, whose page is not yet known, so
/// that is a diagnostic. Page furniture evaluates against a `PageEvalContext`,
/// where page variables are exactly what an expression may use, and passes no
/// [pageRefs].
bool resolveVisibility(
  BoolProperty prop,
  EvalContext ctx,
  ReportDiagnostics diagnostics, {
  required String id,
  Set<String> pageRefs = const <String>{},
}) {
  return prop.getValue((String exprText) {
    final Expression parsed;
    try {
      parsed = Expression.parse(exprText);
    } on ExpressionException catch (e) {
      diagnostics.error('Visibility expression parse failed: ${e.message}',
          elementId: id);
      return true;
    }
    final JetValue value = parsed.evaluate(ctx);
    if (pageRefs.isNotEmpty) {
      diagnostics.error(
          'Page-scoped variable(s) ${pageRefs.join(', ')} are not allowed in a '
          'visibility expression',
          elementId: id);
      return true;
    }
    if (value is JetError) {
      diagnostics.error('Visibility expression error: ${value.message}',
          elementId: id);
      return true;
    }
    if (value is JetBool) return value.value;
    diagnostics.warning(
        'Visibility expression did not evaluate to a boolean; element shown',
        elementId: id);
    return true;
  });
}
