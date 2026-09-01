/// A crosstab (pivot grid) block — spec A.
///
/// Pure domain: the crosstab declares its axes and measures; the aggregator and
/// planner (rendering layer) turn it plus data into bands.
library;

import '../bool_property.dart';
import '../copy_support.dart';
import '../value_equality.dart';
import 'crosstab_group.dart';
import 'crosstab_measure.dart';
import 'crosstab_style.dart';

export 'crosstab_group.dart' show CrosstabSort;

/// An immutable crosstab: [rowGroups] x [columnGroups] of [measures].
///
/// Measures occupy the innermost column axis: each leaf column group is
/// followed by one column per measure.
class Crosstab with ValueEquality {
  /// Creates a crosstab identified by [id].
  const Crosstab({
    required this.id,
    this.name,
    this.collectionField,
    required this.rowGroups,
    required this.columnGroups,
    required this.measures,
    this.style = const CrosstabStyle(),
    this.visible = const BoolProperty(),
  });

  /// Stable identity — the `ct` segment of every cell's element id.
  final String id;

  /// Optional display name; the Outline falls back to a localized label.
  final String? name;

  /// The nested collection this crosstab pools across the scope's rows, or null
  /// to fold the scope's own rows.
  final String? collectionField;

  /// Row axis levels, outermost first. At least one.
  final List<CrosstabGroup> rowGroups;

  /// Column axis levels, outermost first. At least one.
  final List<CrosstabGroup> columnGroups;

  /// The measures, in column order. At least one.
  final List<CrosstabMeasure> measures;

  /// Appearance and metrics.
  final CrosstabStyle style;

  /// Whether the crosstab renders. Evaluated **without a row** (params and
  /// report variables only), since a crosstab prints outside the row loop —
  /// and, because it is resolved once *before* that loop runs, a `$V{}`
  /// reference sees report-start variable values, never values a later row
  /// produces.
  final BoolProperty visible;

  /// Returns a copy with the given fields replaced.
  ///
  /// [name] and [collectionField] are nullable, so they take thunks: omit to
  /// preserve, pass `() => value` to replace (`() => null` clears).
  Crosstab copyWith({
    String? id,
    String? Function()? name,
    String? Function()? collectionField,
    List<CrosstabGroup>? rowGroups,
    List<CrosstabGroup>? columnGroups,
    List<CrosstabMeasure>? measures,
    CrosstabStyle? style,
    BoolProperty? visible,
  }) =>
      Crosstab(
        id: id ?? this.id,
        name: pick(name, this.name),
        collectionField: pick(collectionField, this.collectionField),
        rowGroups: rowGroups ?? this.rowGroups,
        columnGroups: columnGroups ?? this.columnGroups,
        measures: measures ?? this.measures,
        style: style ?? this.style,
        visible: visible ?? this.visible,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        collectionField,
        rowGroups,
        columnGroups,
        measures,
        style,
        visible,
      ];

  @override
  String toString() => 'Crosstab($id, ${rowGroups.length}x'
      '${columnGroups.length}, ${measures.length} measure(s))';
}
