/// The inline-aggregate vocabulary: the five aggregate function
/// names an author may write inline (`SUM`/`AVG`/`COUNT`/`MIN`/`MAX`) and the
/// rule that recognizes a *top-level* aggregate call. Shared by the value
/// template compiler, the aggregate synthesizer, and validation so the surface
/// stays single-sourced.
library;

import '../../domain/report_variable.dart';
import '../ast.dart';

/// The aggregate function names mapped to their fold strategy. `MIN`/`MAX`
/// collide with the scalar math functions of the same name; disambiguation is
/// by arity + band (see [topLevelAggregate] and the synthesizer).
///
/// `JetCalculation.first` and `JetCalculation.last` are intentionally excluded:
/// they are variable-only fold strategies and have no inline-aggregate syntax.
const Map<String, JetCalculation> _aggregates = <String, JetCalculation>{
  'SUM': JetCalculation.sum,
  'AVG': JetCalculation.average,
  'COUNT': JetCalculation.count,
  'MIN': JetCalculation.min,
  'MAX': JetCalculation.max,
};

/// The calculation for aggregate-function [name] (case-insensitive), or null if
/// [name] is not an aggregate function.
JetCalculation? aggregateCalculationFor(String name) =>
    _aggregates[name.toUpperCase()];

/// The aggregate function name for [calculation] (inverse of
/// [aggregateCalculationFor]), or null if [calculation] is not an inline
/// aggregate. Keeps the name table single-sourced for the reverse compiler.
String? aggregateNameFor(JetCalculation calculation) {
  for (final MapEntry<String, JetCalculation> e in _aggregates.entries) {
    if (e.value == calculation) return e.key;
  }
  return null;
}

/// A recognized inline aggregate: its [calculation] and single [argument].
class AggregateCall {
  const AggregateCall(this.calculation, this.argument);

  /// The fold strategy (SUM / AVG / COUNT / MIN / MAX) for this aggregate.
  final JetCalculation calculation;

  /// The single expression passed to the aggregate function (e.g. `$F{price}`).
  final Expr argument;
}

/// Recognizes [expr] as a top-level inline aggregate: a [CallExpr] whose name is
/// an aggregate function with exactly one argument. Returns null otherwise (a
/// multi-arg `MIN`/`MAX` is the scalar function; an aggregate nested inside other
/// syntax is not top-level). The single-arg + band rule is the disambiguation
/// from the scalar `MIN`/`MAX` math functions.
AggregateCall? topLevelAggregate(Expr expr) {
  if (expr is! CallExpr || expr.arguments.length != 1) return null;
  final JetCalculation? calc = aggregateCalculationFor(expr.name);
  if (calc == null) return null;
  return AggregateCall(calc, expr.arguments.single);
}

/// The `$F{}` fields [expr] reads outside every inline aggregate call: what a
/// band with no data row would have to bind directly. An aggregate's operand is
/// folded over the data rows, so its fields are not direct bindings, wherever
/// the call sits in the expression (`SUM($F{debit}) - SUM($F{credit})`,
/// `ROUND(AVG($F{rate}), 2)`) — which is where the aggregate synthesizer lifts
/// it from too (api-friction entry 6).
Set<String> fieldRefsOutsideAggregates(Expr expr) => switch (expr) {
      FieldRefExpr(:final String name) => <String>{name},
      LiteralExpr() || ParamRefExpr() || VariableRefExpr() => const <String>{},
      UnaryExpr(:final Expr operand) => fieldRefsOutsideAggregates(operand),
      BinaryExpr(:final Expr left, :final Expr right) => <String>{
          ...fieldRefsOutsideAggregates(left),
          ...fieldRefsOutsideAggregates(right),
        },
      ConditionalExpr(
        :final Expr condition,
        :final Expr thenBranch,
        :final Expr elseBranch,
      ) =>
        <String>{
          ...fieldRefsOutsideAggregates(condition),
          ...fieldRefsOutsideAggregates(thenBranch),
          ...fieldRefsOutsideAggregates(elseBranch),
        },
      CallExpr() when topLevelAggregate(expr) != null => const <String>{},
      CallExpr(:final List<Expr> arguments) => <String>{
          for (final Expr a in arguments) ...fieldRefsOutsideAggregates(a),
        },
    };

/// Every inline aggregate call in [expr], wherever it sits (`SUM($F{debit}) -
/// SUM($F{credit})` yields both), in source order. An aggregate's own argument
/// is not searched further. These are the calls the synthesizer lifts from a
/// sink band, so they are the operands validation resolves against the schema
/// (api-friction entry 6).
List<AggregateCall> aggregatesIn(Expr expr) {
  final AggregateCall? call = topLevelAggregate(expr);
  if (call != null) return <AggregateCall>[call];
  return switch (expr) {
    FieldRefExpr() ||
    LiteralExpr() ||
    ParamRefExpr() ||
    VariableRefExpr() =>
      const <AggregateCall>[],
    UnaryExpr(:final Expr operand) => aggregatesIn(operand),
    BinaryExpr(:final Expr left, :final Expr right) => <AggregateCall>[
        ...aggregatesIn(left),
        ...aggregatesIn(right),
      ],
    ConditionalExpr(
      :final Expr condition,
      :final Expr thenBranch,
      :final Expr elseBranch,
    ) =>
      <AggregateCall>[
        ...aggregatesIn(condition),
        ...aggregatesIn(thenBranch),
        ...aggregatesIn(elseBranch),
      ],
    CallExpr(:final List<Expr> arguments) => <AggregateCall>[
        for (final Expr a in arguments) ...aggregatesIn(a),
      ],
  };
}
