// AST nodes + canonical toString (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/ast.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  test('nodes render a canonical S-expression', () {
    // (qty * price)  ->  (* (field qty) (field price))
    final Expr e = BinaryExpr(
      BinaryOp.multiply,
      FieldRefExpr('qty'),
      FieldRefExpr('price'),
    );
    expect(e.toString(), '(* (field qty) (field price))');
  });

  test('literal, param, unary, conditional and call render canonically', () {
    expect(LiteralExpr(const JetNumber(5)).toString(), '5.0');
    expect(ParamRefExpr('tax').toString(), '(param tax)');
    expect(
        UnaryExpr(UnaryOp.negate, LiteralExpr(const JetNumber(1))).toString(),
        '(- 1.0)');
    expect(
        ConditionalExpr(
                LiteralExpr(const JetBool(true)),
                LiteralExpr(const JetNumber(1)),
                LiteralExpr(const JetNumber(2)))
            .toString(),
        '(if true 1.0 2.0)');
    expect(
        CallExpr('ROUND', <Expr>[
          FieldRefExpr('x'),
          LiteralExpr(const JetNumber(2))
        ]).toString(),
        '(call ROUND (field x) 2.0)');
  });
}
