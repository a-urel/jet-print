/// A boolean property that is either a static [value] or, when [expression] is
/// non-null, a boolean expression that takes precedence over [value].
///
/// Pure and serializable: it stores the expression as a string and never
/// evaluates it itself (Constitution II — the domain layer must not depend on
/// the expression engine). Evaluation is injected via [getValue].
library;

class BoolProperty {
  /// Creates a property defaulting to visible/true with no expression.
  const BoolProperty({this.value = true, this.expression});

  /// The static fallback, used when [expression] is null.
  final bool value;

  /// When non-null, the boolean expression that governs the result (precedence
  /// over [value]). Null means use [value].
  final String? expression;

  /// Whether an [expression] governs this property.
  bool get hasExpression => expression != null;

  /// Resolves the effective boolean. [evaluate] is supplied by the caller (the
  /// fill layer) so this type stays free of the expression engine.
  bool getValue(bool Function(String expr) evaluate) =>
      expression != null ? evaluate(expression!) : value;

  /// Returns a copy with fields replaced. [expression] is a thunk so callers can
  /// distinguish keep (omit) from clear (`() => null`) and set (`() => v`).
  BoolProperty copyWith({bool? value, String? Function()? expression}) =>
      BoolProperty(
        value: value ?? this.value,
        expression: expression == null ? this.expression : expression(),
      );

  /// Emits only non-default sub-keys; the default (`true`, no expression) is the
  /// empty map (callers omit the owning key entirely).
  Map<String, Object?> toJson() => <String, Object?>{
        if (!value) 'value': false,
        if (expression != null) 'expression': expression,
      };

  /// Reads a [BoolProperty]; a missing `value` defaults to true.
  factory BoolProperty.fromJson(Map<String, Object?> json) => BoolProperty(
        value: json['value'] as bool? ?? true,
        expression: json['expression'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is BoolProperty &&
      other.value == value &&
      other.expression == expression;

  @override
  int get hashCode => Object.hash(value, expression);

  @override
  String toString() => 'BoolProperty($value'
      '${expression == null ? '' : ', expr: "$expression"'})';
}
