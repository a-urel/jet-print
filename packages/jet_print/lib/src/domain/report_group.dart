/// A report group — a reset boundary keyed by an expression (spec 005b).
library;

/// An immutable group definition: a [name] and a key [expression].
///
/// The calculator evaluates [expression] per row; when its value changes
/// between consecutive rows the group "breaks" and its group-scoped variables
/// reset. Groups are ordered (outermost first); an outer break cascades to all
/// inner groups.
class ReportGroup {
  /// Creates a group keyed by [expression].
  const ReportGroup({required this.name, required this.expression});

  /// Reads a [ReportGroup] from its [toJson] map.
  factory ReportGroup.fromJson(Map<String, Object?> json) => ReportGroup(
        name: json['name']! as String,
        expression: json['expression']! as String,
      );

  /// The group name (referenced by a variable's `resetGroup`).
  final String name;

  /// The grouping-key expression (005a syntax).
  final String expression;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'expression': expression};

  @override
  bool operator ==(Object other) =>
      other is ReportGroup &&
      other.name == name &&
      other.expression == expression;

  @override
  int get hashCode => Object.hash(name, expression);

  @override
  String toString() => 'ReportGroup($name, "$expression")';
}
