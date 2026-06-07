/// The expression evaluator: walks an [Expr] against an [EvalContext] producing
/// a [JetValue] (spec 005a). Internal to the expression seam.
///
/// Total by construction: a failed operation returns a [JetError] (a value)
/// rather than throwing, and an error operand propagates upward. Numbers are
/// `double`; `/` and `%` by zero are errors; `+` concatenates two strings;
/// equality is total across types; ordering requires the same orderable type;
/// `&&`/`||`/`?:` short-circuit.
library;

import 'ast.dart';
import 'eval_context.dart';
import 'function_registry.dart';
import 'value.dart';

/// Evaluates [expr] against [context].
JetValue evaluate(Expr expr, EvalContext context) {
  switch (expr) {
    case LiteralExpr(value: final JetValue v):
      return v;
    case FieldRefExpr(name: final String n):
      return context.resolveField(n);
    case ParamRefExpr(name: final String n):
      return context.resolveParam(n);
    case VariableRefExpr(name: final String n):
      return context.resolveVariable(n);
    case UnaryExpr(op: final UnaryOp op, operand: final Expr operand):
      return _unary(op, evaluate(operand, context));
    case BinaryExpr(
        op: final BinaryOp op,
        left: final Expr l,
        right: final Expr r
      ):
      return _binary(op, l, r, context);
    case ConditionalExpr(
        condition: final Expr c,
        thenBranch: final Expr t,
        elseBranch: final Expr e,
      ):
      final JetValue cond = evaluate(c, context);
      return switch (cond) {
        JetError() => cond,
        JetBool(value: final bool b) => evaluate(b ? t : e, context),
        _ => const JetError('Condition of "?:" must be boolean'),
      };
    case CallExpr(name: final String name, arguments: final List<Expr> args):
      return _call(name, args, context);
  }
}

JetValue _unary(UnaryOp op, JetValue v) {
  if (v is JetError) return v;
  return switch (op) {
    UnaryOp.negate => v is JetNumber
        ? JetNumber(-v.value)
        : const JetError('Unary "-" requires a number'),
    UnaryOp.not => v is JetBool
        ? JetBool(!v.value)
        : const JetError('Unary "!" requires a boolean'),
  };
}

JetValue _binary(BinaryOp op, Expr leftExpr, Expr rightExpr, EvalContext ctx) {
  // Short-circuiting logical operators evaluate the right side lazily.
  if (op == BinaryOp.and || op == BinaryOp.or) {
    final String opSym = op == BinaryOp.and ? '&&' : '||';
    final JetValue left = evaluate(leftExpr, ctx);
    if (left is JetError) return left;
    if (left is! JetBool) {
      return JetError('Operator "$opSym" requires booleans');
    }
    if (op == BinaryOp.and && !left.value) return const JetBool(false);
    if (op == BinaryOp.or && left.value) return const JetBool(true);
    final JetValue right = evaluate(rightExpr, ctx);
    if (right is JetError) return right;
    if (right is! JetBool) {
      return JetError('Operator "$opSym" requires booleans');
    }
    return JetBool(right.value);
  }

  final JetValue left = evaluate(leftExpr, ctx);
  if (left is JetError) return left;
  final JetValue right = evaluate(rightExpr, ctx);
  if (right is JetError) return right;

  switch (op) {
    case BinaryOp.equal:
      return JetBool(left == right);
    case BinaryOp.notEqual:
      return JetBool(left != right);
    case BinaryOp.add:
      if (left is JetNumber && right is JetNumber) {
        return JetNumber(left.value + right.value);
      }
      if (left is JetString && right is JetString) {
        return JetString(left.value + right.value);
      }
      return const JetError('Operator "+" requires two numbers or two strings');
    case BinaryOp.subtract:
      return _arith(left, right, '-', (double a, double b) => a - b);
    case BinaryOp.multiply:
      return _arith(left, right, '*', (double a, double b) => a * b);
    case BinaryOp.divide:
      return _arithChecked(left, right, '/', (double a, double b) => a / b);
    case BinaryOp.modulo:
      return _arithChecked(left, right, '%', (double a, double b) => a % b);
    case BinaryOp.less:
      return _order(left, right, (int c) => c < 0, '<');
    case BinaryOp.lessEqual:
      return _order(left, right, (int c) => c <= 0, '<=');
    case BinaryOp.greater:
      return _order(left, right, (int c) => c > 0, '>');
    case BinaryOp.greaterEqual:
      return _order(left, right, (int c) => c >= 0, '>=');
    case BinaryOp.and:
    case BinaryOp.or:
      // Structurally unreachable: && and || are fully handled by the
      // short-circuit block above this switch. Present only to keep the switch
      // exhaustive over BinaryOp (no `default`). Returned as a value, not
      // thrown, to honour the evaluator's never-throws contract.
      return const JetError('Internal error: && / || bypassed short-circuit');
  }
}

JetValue _arith(
    JetValue l, JetValue r, String sym, double Function(double, double) f) {
  if (l is JetNumber && r is JetNumber) return JetNumber(f(l.value, r.value));
  return JetError('Operator "$sym" requires two numbers');
}

JetValue _arithChecked(
    JetValue l, JetValue r, String sym, double Function(double, double) f) {
  if (l is! JetNumber || r is! JetNumber) {
    return JetError('Operator "$sym" requires two numbers');
  }
  if (r.value == 0) return JetError('Division by zero in "$sym"');
  return JetNumber(f(l.value, r.value));
}

JetValue _order(JetValue l, JetValue r, bool Function(int) test, String sym) {
  final int? cmp = _compare(l, r);
  if (cmp == null) {
    return JetError('Operator "$sym" requires two comparable values of the '
        'same type');
  }
  return JetBool(test(cmp));
}

int? _compare(JetValue l, JetValue r) => jetCompare(l, r);

JetValue _call(String name, List<Expr> argExprs, EvalContext ctx) {
  final List<JetValue> args = <JetValue>[];
  for (final Expr argExpr in argExprs) {
    final JetValue v = evaluate(argExpr, ctx);
    if (v is JetError) return v; // auto-propagate the first error argument
    args.add(v);
  }
  final JetExprFn? fn = ctx.functions.lookup(name);
  if (fn == null) return JetError('Unknown function "$name"');
  return fn(args, ctx);
}
