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

  /// Evaluates this expression against [context], returning a [JetValue]
  /// (possibly a [JetError]).
  JetValue evaluate(EvalContext context) => evaluator.evaluate(_root, context);
}
