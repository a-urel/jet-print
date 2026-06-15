/// The inline-aggregate vocabulary (spec 028): the five aggregate function
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
  final JetCalculation calculation;
  final Expr argument;
}

/// Recognizes [expr] as a top-level inline aggregate: a [CallExpr] whose name is
/// an aggregate function with exactly one argument. Returns null otherwise (a
/// multi-arg `MIN`/`MAX` is the scalar function; an aggregate nested inside other
/// syntax is not top-level). The single-arg + band rule is the disambiguation
/// from the scalar `MIN`/`MAX` math functions (FR-005).
AggregateCall? topLevelAggregate(Expr expr) {
  if (expr is! CallExpr || expr.arguments.length != 1) return null;
  final JetCalculation? calc = aggregateCalculationFor(expr.name);
  if (calc == null) return null;
  return AggregateCall(calc, expr.arguments.single);
}
