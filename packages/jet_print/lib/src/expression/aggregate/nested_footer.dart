/// Footer-aggregate preparation for nested collection scopes (spec 029, B1).
///
/// A nested `DetailScope.footer` may hold inline aggregates (Phase A grammar)
/// that sum over the scope's OWN collection. Unlike master-scope aggregates
/// (which `expandAggregates` turns into `ReportVariable`s for the master
/// calculator), these are folded by the filler over the scope's child rows.
/// This pure helper rewrites each aggregate element to a `$V{__naggN}` reference
/// and returns the specs the filler evaluates per child row.
library;

import '../../domain/band.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/report_element.dart';
import '../../domain/report_variable.dart';
import '../expression.dart';
import '../expression_exception.dart';
import 'aggregate_functions.dart';

/// One nested-footer aggregate: the synth variable [name] its element now
/// references, the [calculation], and the [argument] expression folded over
/// each child row.
class NestedAgg {
  /// Creates a nested-footer aggregate spec.
  const NestedAgg(this.name, this.calculation, this.argument);

  /// The synthesized variable name (`__naggN`) the rewritten element references.
  final String name;

  /// The fold strategy (SUM / AVG / COUNT / MIN / MAX).
  final JetCalculation calculation;

  /// The inner expression evaluated per child row before folding.
  final Expression argument;
}

/// The result of preparing a footer: the [band] with aggregate elements
/// rewritten to `$V{__naggN}`, and the [aggs] to fold. Returns the input band
/// unchanged (identical) and empty [aggs] when no element holds an aggregate.
class PreparedFooter {
  /// Creates a prepared-footer result.
  const PreparedFooter(this.band, this.aggs);

  /// The footer band, with aggregate elements rewritten (or the input band
  /// unchanged when there were none).
  final Band band;

  /// The aggregate specs the filler folds over the scope's child rows.
  final List<NestedAgg> aggs;
}

/// Prepares [footer] for filler-local folding: returns the band with each inline
/// aggregate element rewritten to `$V{__naggN}` and the matching [NestedAgg] specs
/// in [PreparedFooter.aggs]; returns [footer] unchanged with no specs when it holds
/// no aggregate. Pure.
PreparedFooter prepareNestedFooter(Band footer) {
  final List<NestedAgg> aggs = <NestedAgg>[];
  bool changed = false;
  final List<ReportElement> els = <ReportElement>[
    for (final ReportElement e in footer.elements)
      _rewrite(e, aggs, () => changed = true),
  ];
  if (!changed) return PreparedFooter(footer, const <NestedAgg>[]);
  return PreparedFooter(footer.copyWith(elements: els), aggs);
}

ReportElement _rewrite(
    ReportElement e, List<NestedAgg> aggs, void Function() mark) {
  if (e is! TextElement || e.expression == null) return e;
  final String expr = e.expression!;
  final AggregateCall? agg;
  try {
    agg = topLevelAggregate(Expression.parse(expr).root);
  } on ExpressionException {
    return e;
  }
  if (agg == null) return e;
  final String inner =
      expr.substring(expr.indexOf('(') + 1, expr.lastIndexOf(')'));
  final String name = '__nagg${aggs.length}';
  aggs.add(NestedAgg(name, agg.calculation, Expression.parse(inner)));
  mark();
  return TextElement(
    id: e.id,
    bounds: e.bounds,
    text: e.text,
    style: e.style,
    expression: '\$V{$name}',
    format: e.format,
  );
}
