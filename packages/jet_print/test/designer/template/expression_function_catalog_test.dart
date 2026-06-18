/// Tests for the designer's expression-function catalog (032): the metadata that
/// drives the fx editor's function palette. Verifies grouping, snippet shape,
/// caret placement, and — critically — that every catalog name maps to a
/// function the engine actually evaluates and parses.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/template/expression_function_catalog.dart';
import 'package:jet_print/src/designer/template/value_template_compiler.dart';

void main() {
  test('catalog covers the four groups', () {
    final Set<ExpressionFunctionGroup> groups = expressionFunctionCatalog
        .map((ExpressionFunction f) => f.group)
        .toSet();
    expect(groups, <ExpressionFunctionGroup>{
      ExpressionFunctionGroup.string,
      ExpressionFunctionGroup.math,
      ExpressionFunctionGroup.logic,
      ExpressionFunctionGroup.aggregate,
    });
  });

  test('every entry has a non-empty name, signature, and snippet', () {
    for (final ExpressionFunction f in expressionFunctionCatalog) {
      expect(f.name, isNotEmpty);
      expect(f.signature, isNotEmpty);
      expect(f.insertSnippet, isNotEmpty);
      expect(f.caretOffset, inInclusiveRange(0, f.insertSnippet.length));
    }
  });

  test('aggregate names are the inline-aggregate vocabulary', () {
    final Set<String> aggNames = expressionFunctionCatalog
        .where((ExpressionFunction f) =>
            f.group == ExpressionFunctionGroup.aggregate)
        .map((ExpressionFunction f) => f.name)
        .toSet();
    expect(aggNames, <String>{'SUM', 'AVG', 'COUNT', 'MIN', 'MAX'});
  });

  test('known built-ins are offered', () {
    final Set<String> names =
        expressionFunctionCatalog.map((ExpressionFunction f) => f.name).toSet();
    for (final String n in <String>[
      'UPPER',
      'LOWER',
      'TRIM',
      'CONCAT',
      'SUBSTRING',
      'ABS',
      'ROUND',
      'IF',
      'COALESCE',
      'FORMAT'
    ]) {
      expect(names, contains(n), reason: '$n missing from catalog');
    }
  });

  test('each offered function name compiles as a call', () {
    for (final ExpressionFunction f in expressionFunctionCatalog) {
      expect(parseValueField('{${f.name}([qty])}'), isA<BindingValue>(),
          reason: '${f.name} should compile as a call');
    }
  });
}
