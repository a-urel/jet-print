/// A named roll-up total published by a nested [DetailScope] (spec 030, B2).
///
/// [expression] is a top-level inline aggregate (Phase A grammar, e.g.
/// `SUM($F{lineTotal})`) folded over the scope's child rows; the result is
/// injected as a field named [name] on the scope's PARENT row, so an enclosing
/// scope, a group footer, or the report summary can reference it as `$F{name}`.
library;

import 'value_equality.dart';

/// An immutable `{name, expression}` published total.
class ScopeTotal with ValueEquality {
  /// Creates a published total binding [name] to the aggregate [expression].
  const ScopeTotal(this.name, this.expression);

  /// The field name this total is injected under on the parent row.
  final String name;

  /// The stored top-level aggregate (e.g. `SUM($F{lineTotal})`).
  final String expression;

  @override
  List<Object?> get props => <Object?>[name, expression];

  @override
  String toString() => 'ScopeTotal($name = $expression)';
}
