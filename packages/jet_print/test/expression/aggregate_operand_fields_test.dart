library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression.dart';

void main() {
  test('reports the operand of a top-level aggregate', () {
    expect(Expression.parse(r'SUM($F{lineTotal})').aggregateOperandFields,
        <String>{'lineTotal'});
  });

  test('reports operands of aggregate sub-terms in a compound expression', () {
    expect(
      Expression.parse(r'SUM($F{lineTotal}) + COUNT($F{orderNo})')
          .aggregateOperandFields,
      <String>{'lineTotal', 'orderNo'},
    );
  });

  test('a bare field reference is not an aggregate operand', () {
    expect(Expression.parse(r'$F{lineTotal}').aggregateOperandFields, isEmpty);
  });

  test('a non-aggregate call argument is not an aggregate operand', () {
    expect(Expression.parse(r'UPPER($F{name})').aggregateOperandFields, isEmpty);
  });

  test('a field used both bare and as an operand is reported (operand wins)',
      () {
    expect(
      Expression.parse(r'SUM($F{x}) + $F{x}').aggregateOperandFields,
      <String>{'x'},
    );
  });
}
