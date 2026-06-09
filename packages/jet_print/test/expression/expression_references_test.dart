// Expression.references: complete, branch-independent reference analysis (008c).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression.dart';

void main() {
  group('Expression.references', () {
    test('collects field, param, and variable references by kind', () {
      final ({
        Set<String> fields,
        Set<String> params,
        Set<String> variables
      }) refs = Expression.parse(r'$F{a} + $P{b} + $V{c}').references;
      expect(refs.fields, <String>{'a'});
      expect(refs.params, <String>{'b'});
      expect(refs.variables, <String>{'c'});
    });

    test('walks ALL branches of a conditional (not just the taken one)', () {
      final ({
        Set<String> fields,
        Set<String> params,
        Set<String> variables
      }) refs = Expression.parse(r'$V{PAGE_NUMBER} == "1" ? $F{x} : $P{y}')
          .references;
      expect(refs.fields, <String>{'x'});
      expect(refs.params, <String>{'y'});
      expect(refs.variables, <String>{'PAGE_NUMBER'});
    });

    test('walks the short-circuited side of &&', () {
      // `false && $F{x}` never evaluates the RHS at runtime; static analysis
      // still sees the field reference.
      final ({
        Set<String> fields,
        Set<String> params,
        Set<String> variables
      }) refs = Expression.parse(r'false && $F{x}').references;
      expect(refs.fields, <String>{'x'});
    });

    test('walks function-call arguments', () {
      final ({
        Set<String> fields,
        Set<String> params,
        Set<String> variables
      }) refs = Expression.parse(r'CONCAT($F{a}, $P{b})').references;
      expect(refs.fields, <String>{'a'});
      expect(refs.params, <String>{'b'});
    });

    test('ignores sigil-like text inside a string literal', () {
      final ({
        Set<String> fields,
        Set<String> params,
        Set<String> variables
      }) refs = Expression.parse(r"'a $F{x} literal'").references;
      expect(refs.fields, isEmpty);
      expect(refs.params, isEmpty);
      expect(refs.variables, isEmpty);
    });
  });
}
