/// One level of a crosstab axis (spec A): a named group whose per-row
/// [expression] produces the key rows are bucketed by.
library;

import '../copy_support.dart';
import '../value_equality.dart';

/// How a [CrosstabGroup]'s keys are ordered on its axis.
enum CrosstabSort {
  /// Ascending by the typed group key.
  ascending,

  /// Descending by the typed group key.
  descending,

  /// The order keys were first seen while folding rows.
  dataOrder,
}

/// An immutable crosstab axis level.
class CrosstabGroup with ValueEquality {
  /// Creates an axis level identified by [id], labelled [name], bucketing rows
  /// by [expression].
  const CrosstabGroup({
    required this.id,
    required this.name,
    required this.expression,
    this.sort = CrosstabSort.ascending,
    this.showTotal = true,
    this.totalLabel,
  });

  /// Stable identity.
  final String id;

  /// Display label.
  final String name;

  /// Per-row group key, a canonical expression string (e.g. `$F{region}`).
  final String expression;

  /// How this level's keys are ordered.
  final CrosstabSort sort;

  /// Whether this level emits a subtotal. On the outermost level this is the
  /// grand total — there is no separate grand-total flag.
  final bool showTotal;

  /// Overrides the total's printed label, or null for the default.
  ///
  /// The default is `'∑ <parent label>'` — the label of the node the total
  /// collapses this level within (`∑ North`), since a total addresses that
  /// parent's path. The grand total has no parent, so its default is
  /// `'∑ Total'`. (`planCrosstab` builds these; this level's own [name] is
  /// not part of the default.)
  final String? totalLabel;

  /// Returns a copy with the given fields replaced.
  ///
  /// [totalLabel] is nullable, so it takes a thunk: omit to preserve, pass
  /// `() => value` to replace (`() => null` clears).
  CrosstabGroup copyWith({
    String? id,
    String? name,
    String? expression,
    CrosstabSort? sort,
    bool? showTotal,
    String? Function()? totalLabel,
  }) =>
      CrosstabGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        expression: expression ?? this.expression,
        sort: sort ?? this.sort,
        showTotal: showTotal ?? this.showTotal,
        totalLabel: pick(totalLabel, this.totalLabel),
      );

  @override
  List<Object?> get props =>
      <Object?>[id, name, expression, sort, showTotal, totalLabel];

  @override
  String toString() => 'CrosstabGroup($id, $name'
      '${showTotal ? ', total' : ''})';
}
