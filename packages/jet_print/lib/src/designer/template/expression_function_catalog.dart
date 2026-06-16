/// The fx editor's function palette metadata (032). Presentation-only: the
/// engine's `JetFunctionRegistry` carries no UI data, so grouping, insert
/// snippets, caret positions, and signature labels live here. Aggregate names
/// stay single-sourced via [aggregateCalculationFor].
///
/// New engine function → add an entry here (a catalog test asserts the offered
/// names all compile as calls).
library;

import '../../expression/aggregate/aggregate_functions.dart';

/// The palette section an [ExpressionFunction] belongs to.
enum ExpressionFunctionGroup { string, math, logic, aggregate }

/// One palette entry: the registry [name], its [group], a human [signature]
/// label, the friendly-syntax [insertSnippet] dropped into the editor, and the
/// [caretOffset] (within the snippet) where the caret lands after insertion.
class ExpressionFunction {
  const ExpressionFunction({
    required this.name,
    required this.group,
    required this.signature,
    required this.insertSnippet,
    required this.caretOffset,
  });

  final String name;
  final ExpressionFunctionGroup group;
  final String signature;
  final String insertSnippet;
  final int caretOffset;
}

/// Builds an `NAME()` snippet with the caret just inside the opening paren.
ExpressionFunction _fn(
  String name,
  ExpressionFunctionGroup group,
  String signature,
) {
  final String snippet = '$name()';
  return ExpressionFunction(
    name: name,
    group: group,
    signature: signature,
    insertSnippet: snippet,
    caretOffset: name.length + 1, // just after '('
  );
}

/// The functions offered by the fx editor, grouped for display. Aggregate names
/// derive from the inline-aggregate vocabulary so they cannot drift.
final List<ExpressionFunction> expressionFunctionCatalog = <ExpressionFunction>[
  // String
  _fn('UPPER', ExpressionFunctionGroup.string, 'UPPER(text)'),
  _fn('LOWER', ExpressionFunctionGroup.string, 'LOWER(text)'),
  _fn('TRIM', ExpressionFunctionGroup.string, 'TRIM(text)'),
  _fn('LENGTH', ExpressionFunctionGroup.string, 'LENGTH(text)'),
  _fn('CONCAT', ExpressionFunctionGroup.string, 'CONCAT(a, b, …)'),
  _fn(
    'SUBSTRING',
    ExpressionFunctionGroup.string,
    'SUBSTRING(text, start, len)',
  ),
  _fn('FORMAT', ExpressionFunctionGroup.string, 'FORMAT(value, pattern)'),
  // Math
  _fn('ABS', ExpressionFunctionGroup.math, 'ABS(number)'),
  _fn('ROUND', ExpressionFunctionGroup.math, 'ROUND(number, places)'),
  _fn('CEIL', ExpressionFunctionGroup.math, 'CEIL(number)'),
  _fn('FLOOR', ExpressionFunctionGroup.math, 'FLOOR(number)'),
  _fn('MIN', ExpressionFunctionGroup.math, 'MIN(a, b)'),
  _fn('MAX', ExpressionFunctionGroup.math, 'MAX(a, b)'),
  // Logic
  _fn('IF', ExpressionFunctionGroup.logic, 'IF(cond, then, else)'),
  _fn('COALESCE', ExpressionFunctionGroup.logic, 'COALESCE(a, b, …)'),
  _fn('ISNULL', ExpressionFunctionGroup.logic, 'ISNULL(value)'),
  // Aggregate — names from the single-sourced vocabulary.
  for (final String n in const <String>['SUM', 'AVG', 'COUNT', 'MIN', 'MAX'])
    if (aggregateCalculationFor(n) != null)
      _fn(n, ExpressionFunctionGroup.aggregate, '$n(expression)'),
];
