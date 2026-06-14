/// A report variable — a named accumulated/derived value (spec 005b).
library;

/// How a [ReportVariable] folds its per-row expression values.
enum JetCalculation {
  /// No folding — the variable's value is its expression evaluated each row.
  none,

  /// Running sum of numeric values.
  sum,

  /// Count of non-null values.
  count,

  /// Mean of numeric values.
  average,

  /// Running minimum (same-type orderable values).
  min,

  /// Running maximum (same-type orderable values).
  max,

  /// The first contributable value in the reset scope.
  first,

  /// The most recent contributable value in the reset scope.
  last,
}

/// When a [ReportVariable]'s accumulator resets.
enum VariableResetScope {
  /// Resets once at report start (grand total / running total).
  report,

  /// Resets when the named group's key changes (group subtotal).
  group,
}

/// An immutable variable definition.
class ReportVariable {
  /// Creates a variable named [name] folding [expression] via [calculation],
  /// resetting at [resetScope] (and [resetGroup] when scoped to a group).
  const ReportVariable({
    required this.name,
    required this.expression,
    this.calculation = JetCalculation.none,
    this.resetScope = VariableResetScope.report,
    this.resetGroup,
  });

  /// Reads a [ReportVariable] from its [toJson] map.
  factory ReportVariable.fromJson(Map<String, Object?> json) => ReportVariable(
        name: json['name']! as String,
        expression: json['expression']! as String,
        calculation: json['calculation'] == null
            ? JetCalculation.none
            : JetCalculation.values.byName(json['calculation']! as String),
        resetScope: json['resetScope'] == null
            ? VariableResetScope.report
            : VariableResetScope.values.byName(json['resetScope']! as String),
        resetGroup: json['resetGroup'] as String?,
      );

  /// The variable name, as referenced by `$V{name}`.
  final String name;

  /// The per-row expression to fold (005a syntax).
  final String expression;

  /// How per-row values fold into the accumulator.
  final JetCalculation calculation;

  /// When the accumulator resets.
  final VariableResetScope resetScope;

  /// The group whose break resets this variable (when [resetScope] is
  /// [VariableResetScope.group]); otherwise `null`.
  ///
  /// In the legacy `ReportTemplate` model this is a `ReportGroup` **name**. In
  /// the reified model (spec 024) it is a `GroupLevel` **id** (FR-003a); the
  /// 1→2 migration rewrites each name to the matching group id.
  final String? resetGroup;

  /// Serializes to a JSON-safe map (defaults omitted).
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'expression': expression,
        if (calculation != JetCalculation.none) 'calculation': calculation.name,
        if (resetScope != VariableResetScope.report)
          'resetScope': resetScope.name,
        if (resetGroup != null) 'resetGroup': resetGroup,
      };

  @override
  bool operator ==(Object other) =>
      other is ReportVariable &&
      other.name == name &&
      other.expression == expression &&
      other.calculation == calculation &&
      other.resetScope == resetScope &&
      other.resetGroup == resetGroup;

  @override
  int get hashCode =>
      Object.hash(name, expression, calculation, resetScope, resetGroup);

  @override
  String toString() =>
      'ReportVariable($name, "$expression", $calculation, $resetScope'
      '${resetGroup == null ? '' : ', group: $resetGroup'})';
}
