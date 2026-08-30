/// A crosstab measure (spec A): a per-row [expression] folded by [aggregate]
/// into every cell it contributes to.
library;

import '../copy_support.dart';
import '../report_variable.dart' show JetCalculation;
import '../styles/box_style.dart';
import '../styles/text_style.dart';
import '../value_equality.dart';

/// An immutable measure definition.
class CrosstabMeasure with ValueEquality {
  /// Creates a measure identified by [id], labelled [name].
  const CrosstabMeasure({
    required this.id,
    required this.name,
    required this.expression,
    required this.aggregate,
    this.format,
    this.cellTextStyle,
    this.cellBoxStyle,
  });

  /// Stable identity — also the `m` segment of a cell's element id.
  final String id;

  /// Column header label for this measure.
  final String name;

  /// Per-row value, a canonical expression string (e.g. `$F{qty} * $F{price}`).
  final String expression;

  /// How per-row values fold into a cell. [JetCalculation.none] is rejected by
  /// `validate()` — a cell has no single row to pass through.
  final JetCalculation aggregate;

  /// Optional number/date pattern applied to the folded value.
  final String? format;

  /// Overrides `CrosstabStyle.cellText` for this measure's cells.
  final JetTextStyle? cellTextStyle;

  /// Overrides `CrosstabStyle.cellBox` for this measure's cells.
  final JetBoxStyle? cellBoxStyle;

  /// Returns a copy with the given fields replaced.
  ///
  /// The nullable slots take thunks: omit to preserve, pass `() => value` to
  /// replace (`() => null` clears).
  CrosstabMeasure copyWith({
    String? id,
    String? name,
    String? expression,
    JetCalculation? aggregate,
    String? Function()? format,
    JetTextStyle? Function()? cellTextStyle,
    JetBoxStyle? Function()? cellBoxStyle,
  }) =>
      CrosstabMeasure(
        id: id ?? this.id,
        name: name ?? this.name,
        expression: expression ?? this.expression,
        aggregate: aggregate ?? this.aggregate,
        format: pick(format, this.format),
        cellTextStyle: pick(cellTextStyle, this.cellTextStyle),
        cellBoxStyle: pick(cellBoxStyle, this.cellBoxStyle),
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        expression,
        aggregate,
        format,
        cellTextStyle,
        cellBoxStyle,
      ];

  @override
  String toString() => 'CrosstabMeasure($id, ${aggregate.name})';
}
