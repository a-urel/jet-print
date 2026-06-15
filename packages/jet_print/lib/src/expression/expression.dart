/// A compiled, reusable expression (spec 005a).
library;

import 'ast.dart';
import 'eval_context.dart';
import 'evaluator.dart' as evaluator;
import 'lexer.dart';
import 'parser.dart';
import 'value.dart';

/// A parsed expression that can be evaluated repeatedly against different
/// [EvalContext]s (e.g. once per row during Fill).
///
/// Parsing is eager and throws an `ExpressionException` on malformed input;
/// evaluation never throws — a failed operation yields a [JetError] value.
class Expression {
  const Expression._(this._root);

  final Expr _root;

  /// Compiles [source] into an [Expression].
  ///
  /// Throws an `ExpressionException` if [source] is not a valid expression.
  factory Expression.parse(String source) =>
      Expression._(Parser(tokenize(source)).parseExpression());

  /// The parsed AST root (internal seam — used by the aggregate synthesizer and
  /// the value-template compiler to inspect/rewrite expressions).
  Expr get root => _root;

  /// Evaluates this expression against [context], returning a [JetValue]
  /// (possibly a [JetError]).
  JetValue evaluate(EvalContext context) => evaluator.evaluate(_root, context);

  /// The references this expression makes, grouped by kind (`$F{}` fields,
  /// `$P{}` params, `$V{}` variables). Walks the whole AST — every branch,
  /// operand, and argument — so it is complete and independent of runtime
  /// short-circuiting (unlike evaluation). Text inside a string literal is not a
  /// reference. Used by Layout to validate page-scoped chrome expressions (008c).
  ({Set<String> fields, Set<String> params, Set<String> variables})
      get references {
    final Set<String> fields = <String>{};
    final Set<String> params = <String>{};
    final Set<String> variables = <String>{};
    void walk(Expr node) {
      switch (node) {
        case LiteralExpr():
          break;
        case FieldRefExpr(name: final String n):
          fields.add(n);
        case ParamRefExpr(name: final String n):
          params.add(n);
        case VariableRefExpr(name: final String n):
          variables.add(n);
        case UnaryExpr(operand: final Expr o):
          walk(o);
        case BinaryExpr(left: final Expr l, right: final Expr r):
          walk(l);
          walk(r);
        case ConditionalExpr(
            condition: final Expr c,
            thenBranch: final Expr t,
            elseBranch: final Expr e
          ):
          walk(c);
          walk(t);
          walk(e);
        case CallExpr(arguments: final List<Expr> args):
          for (final Expr a in args) {
            walk(a);
          }
      }
    }

    walk(_root);
    return (fields: fields, params: params, variables: variables);
  }
}
