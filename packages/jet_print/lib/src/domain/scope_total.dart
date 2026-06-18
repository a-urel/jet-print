/// A named roll-up total published by a nested [DetailScope] (spec 030, B2).
///
/// [expression] is a top-level inline aggregate (Phase A grammar, e.g.
/// `SUM($F{lineTotal})`) folded over the scope's child rows; the result is
/// injected as a field named [name] on the scope's PARENT row, so an enclosing
/// scope, a group footer, or the report summary can reference it as `$F{name}`.
library;

/// An immutable `{name, expression}` published total.
class ScopeTotal {
  /// Creates a published total binding [name] to the aggregate [expression].
  const ScopeTotal(this.name, this.expression);

  /// The field name this total is injected under on the parent row.
  final String name;

  /// The stored top-level aggregate (e.g. `SUM($F{lineTotal})`).
  final String expression;

  @override
  bool operator ==(Object other) =>
      other is ScopeTotal &&
      other.name == name &&
      other.expression == expression;

  @override
  int get hashCode => Object.hash(name, expression);

  @override
  String toString() => 'ScopeTotal($name = $expression)';
}
