// Evaluator semantics via the Expression facade (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src, {DataRow? row, Map<String, Object?>? params}) {
  final RowEvalContext ctx = RowEvalContext(
    row: row,
    params: params ?? const <String, Object?>{},
    functions: JetFunctionRegistry(),
  );
  return Expression.parse(src).evaluate(ctx);
}

DataRow _row() => DataRow(
      fields: const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('price', type: JetFieldType.double),
        FieldDef('note', type: JetFieldType.string),
      ],
      values: <String, Object?>{'qty': 3, 'price': 4.0, 'note': null},
    );

void main() {
  group('literals & references', () {
    test('evaluates literals', () {
      expect(_eval('5'), const JetNumber(5));
      expect(_eval("'hi'"), const JetString('hi'));
      expect(_eval('true'), const JetBool(true));
      expect(_eval('null'), const JetNull());
    });

    test('resolves field and param refs', () {
      expect(_eval(r'$F{qty}', row: _row()), const JetNumber(3));
      expect(_eval(r'$P{tax}', params: <String, Object?>{'tax': 0.2}),
          const JetNumber(0.2));
    });
  });

  group('arithmetic (all-double)', () {
    test('adds, subtracts, multiplies, divides', () {
      expect(_eval('1 + 2'), const JetNumber(3));
      expect(_eval('5 - 1'), const JetNumber(4));
      expect(_eval('2 * 3'), const JetNumber(6));
      expect(_eval('7 / 2'), const JetNumber(3.5));
      expect(_eval('7 % 3'), const JetNumber(1));
    });

    test('computes field arithmetic', () {
      expect(_eval(r'$F{qty} * $F{price}', row: _row()), const JetNumber(12));
    });

    test('unary minus negates', () {
      expect(_eval('-(2 + 3)'), const JetNumber(-5));
    });

    test('division and modulo by zero are errors', () {
      expect(_eval('1 / 0'), isA<JetError>());
      expect(_eval('1 % 0'), isA<JetError>());
    });

    test('arithmetic with null or wrong type is an error', () {
      expect(_eval(r'$F{note} + 1', row: _row()), isA<JetError>());
      expect(_eval("'x' * 2"), isA<JetError>());
    });
  });

  group('string concatenation', () {
    test('+ concatenates two strings', () {
      expect(_eval("'a' + 'b'"), const JetString('ab'));
    });

    test('+ on string and number is an error (use CONCAT)', () {
      expect(_eval("'a' + 1"), isA<JetError>());
    });
  });

  group('comparison & equality', () {
    test('numeric comparisons', () {
      expect(_eval('1 < 2'), const JetBool(true));
      expect(_eval('2 <= 2'), const JetBool(true));
      expect(_eval('3 > 5'), const JetBool(false));
    });

    test('equality is total across types', () {
      expect(_eval('1 == 1'), const JetBool(true));
      expect(_eval("1 == '1'"), const JetBool(false));
      expect(_eval('null == null'), const JetBool(true));
      expect(_eval('1 != 2'), const JetBool(true));
    });

    test('ordering across incompatible types is an error', () {
      expect(_eval("1 < 'a'"), isA<JetError>());
      expect(_eval('null < 1'), isA<JetError>());
    });
  });

  group('logical & ternary (short-circuit)', () {
    test('and/or evaluate booleans', () {
      expect(_eval('true && false'), const JetBool(false));
      expect(_eval('false || true'), const JetBool(true));
      expect(_eval('!false'), const JetBool(true));
    });

    test('and short-circuits a failing right operand', () {
      expect(_eval('false && (1 / 0 == 0)'), const JetBool(false));
    });

    test('or short-circuits a failing right operand', () {
      expect(_eval('true || (1 / 0 == 0)'), const JetBool(true));
    });

    test('a non-boolean left operand is an error (right not evaluated)', () {
      expect(_eval('1 && (1 / 0 == 0)'), isA<JetError>());
    });

    test('non-boolean logical operand is an error', () {
      expect(_eval('1 && true'), isA<JetError>());
    });

    test('ternary evaluates only the taken branch', () {
      expect(_eval('true ? 1 : (1 / 0)'), const JetNumber(1));
      expect(_eval('false ? (1 / 0) : 2'), const JetNumber(2));
    });

    test('non-boolean ternary condition is an error', () {
      expect(_eval("'x' ? 1 : 2"), isA<JetError>());
    });
  });

  group('function calls & error propagation', () {
    test('an unknown function is an error', () {
      expect(_eval('NOPE(1)'), isA<JetError>());
    });

    test('a JetError argument propagates without calling the function', () {
      // DOUBLE is unregistered, but the error short-circuits first anyway.
      expect(_eval('DOUBLE(1 / 0)'), isA<JetError>());
    });

    test('calls a registered function', () {
      final RowEvalContext ctx =
          RowEvalContext(functions: JetFunctionRegistry());
      ctx.functions.register(
          'INC',
          (List<JetValue> a, EvalContext c) => switch (a.first) {
                JetNumber(value: final double v) => JetNumber(v + 1),
                _ => const JetError('INC expects a number'),
              });
      expect(Expression.parse('INC(41)').evaluate(ctx), const JetNumber(42));
    });
  });
}
