/// Published-total preparation for nested collection scopes (spec 030, B2).
///
/// A nested `DetailScope.totals` holds named top-level aggregates (Phase A
/// grammar) summing over the scope's OWN child rows. This pure helper parses
/// each into a fold spec the filler evaluates per child row, then injects the
/// result as a field on the parent row. Sibling to `nested_footer.dart` (which
/// rewrites a footer band); here there is no band — totals are pure data.
library;

import '../../domain/report_variable.dart';
import '../../domain/scope_total.dart';
import '../expression.dart';
import '../expression_exception.dart';
import 'aggregate_functions.dart';

/// One published total: its [name], fold [calculation], and [argument] folded
/// over each child row.
class ScopeAgg {
  /// Creates a published-total fold spec.
  const ScopeAgg(this.name, this.calculation, this.argument);

  /// The field name the folded value is injected under on the parent row.
  final String name;

  /// The fold strategy (SUM / AVG / COUNT / MIN / MAX).
  final JetCalculation calculation;

  /// The inner expression evaluated per child row before folding.
  final Expression argument;
}

/// Parses each top-level-aggregate [ScopeTotal] into a [ScopeAgg]; a total whose
/// expression is not a parseable top-level aggregate is skipped. Pure.
List<ScopeAgg> prepareScopeTotals(List<ScopeTotal> totals) {
  final List<ScopeAgg> out = <ScopeAgg>[];
  for (final ScopeTotal t in totals) {
    final AggregateCall? agg;
    try {
      agg = topLevelAggregate(Expression.parse(t.expression).root);
    } on ExpressionException {
      continue;
    }
    if (agg == null) continue;
    final String inner = t.expression.substring(
        t.expression.indexOf('(') + 1, t.expression.lastIndexOf(')'));
    out.add(ScopeAgg(t.name, agg.calculation, Expression.parse(inner)));
  }
  return out;
}
