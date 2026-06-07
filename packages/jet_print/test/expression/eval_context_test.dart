// EvalContext + function registry + RowEvalContext (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

DataRow _row() => DataRow(
      fields: const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('note', type: JetFieldType.string),
      ],
      values: <String, Object?>{'qty': 3, 'note': null},
    );

void main() {
  group('JetFunctionRegistry', () {
    test('registers and looks up functions; unknown is null', () {
      final JetFunctionRegistry r = JetFunctionRegistry();
      JetValue fn(List<JetValue> a, EvalContext c) => const JetNumber(42);
      r.register('ANSWER', fn);
      expect(r.lookup('ANSWER'), same(fn));
      expect(r.lookup('MISSING'), isNull);
    });

    test('register overwrites an existing name', () {
      final JetFunctionRegistry r = JetFunctionRegistry();
      r.register('F', (List<JetValue> a, EvalContext c) => const JetNumber(1));
      r.register('F', (List<JetValue> a, EvalContext c) => const JetNumber(2));
      expect(r.lookup('F')!(<JetValue>[], _CtxStub()), const JetNumber(2));
    });
  });

  group('RowEvalContext', () {
    test('resolves a field to its lifted value (int -> JetNumber)', () {
      final RowEvalContext ctx =
          RowEvalContext(row: _row(), functions: JetFunctionRegistry());
      expect(ctx.resolveField('qty'), const JetNumber(3));
    });

    test('resolves a declared-null field to JetNull', () {
      final RowEvalContext ctx =
          RowEvalContext(row: _row(), functions: JetFunctionRegistry());
      expect(ctx.resolveField('note'), const JetNull());
    });

    test('resolves a missing field to JetNull (render-blank policy)', () {
      final RowEvalContext ctx =
          RowEvalContext(row: _row(), functions: JetFunctionRegistry());
      expect(ctx.resolveField('absent'), const JetNull());
    });

    test('resolves params from the map; missing param is JetNull', () {
      final RowEvalContext ctx = RowEvalContext(
        row: _row(),
        params: <String, Object?>{'tax': 0.2},
        functions: JetFunctionRegistry(),
      );
      expect(ctx.resolveParam('tax'), const JetNumber(0.2));
      expect(ctx.resolveParam('missing'), const JetNull());
    });

    test('resolves fields to JetNull when there is no row', () {
      final RowEvalContext ctx =
          RowEvalContext(functions: JetFunctionRegistry());
      expect(ctx.resolveField('qty'), const JetNull());
    });

    test('exposes its function registry', () {
      final JetFunctionRegistry r = JetFunctionRegistry();
      expect(RowEvalContext(functions: r).functions, same(r));
    });
  });
}

class _CtxStub implements EvalContext {
  @override
  JetFunctionRegistry get functions => JetFunctionRegistry();
  @override
  JetValue resolveField(String name) => const JetNull();
  @override
  JetValue resolveParam(String name) => const JetNull();
}
