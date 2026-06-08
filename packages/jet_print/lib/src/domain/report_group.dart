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
  const ReportGroup({
    required this.name,
    required this.expression,
    this.keepTogether = false,
    this.reprintHeaderOnEachPage = false,
  });

  /// Reads a [ReportGroup] from its [toJson] map.
  factory ReportGroup.fromJson(Map<String, Object?> json) => ReportGroup(
        name: json['name']! as String,
        expression: json['expression']! as String,
        keepTogether: json['keepTogether'] as bool? ?? false,
        reprintHeaderOnEachPage:
            json['reprintHeaderOnEachPage'] as bool? ?? false,
      );

  /// The group name (referenced by a variable's `resetGroup`).
  final String name;

  /// The grouping-key expression (005a syntax).
  final String expression;

  /// When true, the layout engine tries to keep this group's whole instance on
  /// one page — moving it to a fresh page if it does not fit the remainder but
  /// fits a fresh page (008b). Default false.
  final bool keepTogether;

  /// When true, this group's header band(s) are reprinted at the top of each
  /// continuation page the group spans (008b). Default false.
  final bool reprintHeaderOnEachPage;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'expression': expression,
        if (keepTogether) 'keepTogether': true,
        if (reprintHeaderOnEachPage) 'reprintHeaderOnEachPage': true,
      };

  @override
  bool operator ==(Object other) =>
      other is ReportGroup &&
      other.name == name &&
      other.expression == expression &&
      other.keepTogether == keepTogether &&
      other.reprintHeaderOnEachPage == reprintHeaderOnEachPage;

  @override
  int get hashCode =>
      Object.hash(name, expression, keepTogether, reprintHeaderOnEachPage);

  @override
  String toString() => 'ReportGroup($name, "$expression"'
      '${keepTogether ? ', keepTogether' : ''}'
      '${reprintHeaderOnEachPage ? ', reprintHeaderOnEachPage' : ''})';
}
