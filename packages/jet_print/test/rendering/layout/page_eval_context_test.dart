// PageEvalContext: page-scoped value resolution for chrome substitution (008c).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/layout/page_eval_context.dart';

void main() {
  group('PageEvalContext', () {
    PageEvalContext ctx({
      int pageNumber = 1,
      int pageCount = 1,
      Map<String, JetValue> params = const <String, JetValue>{},
    }) =>
        PageEvalContext(
          pageNumber: pageNumber,
          pageCount: pageCount,
          params: params,
          functions: JetFunctionRegistry(),
        );

    test('PAGE_NUMBER and PAGE_COUNT resolve as integer strings', () {
      final EvalContext c = ctx(pageNumber: 2, pageCount: 5);
      expect(c.resolveVariable('PAGE_NUMBER'), const JetString('2'));
      expect(c.resolveVariable('PAGE_COUNT'), const JetString('5'));
    });

    test('a non-page variable resolves to null', () {
      expect(ctx().resolveVariable('total'), const JetNull());
    });

    test('params resolve from the map; an absent param is null', () {
      final EvalContext c =
          ctx(params: <String, JetValue>{'title': const JetString('Q1')});
      expect(c.resolveParam('title'), const JetString('Q1'));
      expect(c.resolveParam('missing'), const JetNull());
    });

    test('fields resolve to null (no data row at page scope)', () {
      expect(ctx().resolveField('anything'), const JetNull());
    });
  });
}
