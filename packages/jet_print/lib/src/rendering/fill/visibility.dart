/// Fill-time evaluation of an object's [BoolProperty] visibility (elements and
/// bands share this). Fail-safe: any parse error, evaluation error, page-scoped
/// variable use, or non-boolean result keeps the object VISIBLE and records a
/// diagnostic, so a broken expression never silently drops content.
library;

import '../../domain/bool_property.dart';
import '../../expression/expression.dart';
import '../../expression/expression_exception.dart';
import '../../expression/value.dart';
import 'fill_eval_context.dart';
import 'report_diagnostics.dart';

/// Returns whether the object is visible. [pageRefs] is the set the [ctx] fills
/// when a page-scoped variable is referenced (illegal here → diagnostic).
bool resolveVisibility(
  BoolProperty prop,
  FillEvalContext ctx,
  ReportDiagnostics diagnostics, {
  required String id,
  required Set<String> pageRefs,
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
