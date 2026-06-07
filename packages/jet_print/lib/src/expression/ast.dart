/// The expression abstract syntax tree (spec 005a). Internal to the expression
/// seam: the parser builds these nodes and the evaluator walks them.
library;

import 'value.dart';

/// A unary operator.
enum UnaryOp {
  /// Arithmetic negation `-x`.
  negate,

  /// Logical not `!x`.
  not,
}

/// A binary operator.
enum BinaryOp {
  /// `+`
  add,

  /// `-`
  subtract,

  /// `*`
  multiply,

  /// `/`
  divide,

  /// `%`
  modulo,

  /// `==`
  equal,

  /// `!=`
  notEqual,

  /// `<`
  less,

  /// `<=`
  lessEqual,

  /// `>`
  greater,

  /// `>=`
  greaterEqual,

  /// `&&`
  and,

  /// `||`
  or,
}

/// A node in the expression AST.
sealed class Expr {
  const Expr();
}

/// A constant literal value.
final class LiteralExpr extends Expr {
  /// Creates a literal node.
  const LiteralExpr(this.value);

  /// The literal value.
  final JetValue value;

  // Debug/canonical rendering for tests — NOT the display path. Strings are
  // quoted, and null is rendered as `JetNull()` (distinct from jetStringify's
  // display blank `''`, which would be ambiguous in an S-expression). Display
  // text comes from the evaluator + jetStringify, never from here.
  @override
  String toString() => switch (value) {
        JetString(value: final String s) => "'$s'",
        JetNull() => 'JetNull()',
        _ => jetStringify(value),
      };
}

/// A field reference `$F{name}`.
final class FieldRefExpr extends Expr {
  /// Creates a field reference node.
  const FieldRefExpr(this.name);

  /// The field name.
  final String name;

  @override
  String toString() => '(field $name)';
}

/// A parameter reference `$P{name}`.
final class ParamRefExpr extends Expr {
  /// Creates a parameter reference node.
  const ParamRefExpr(this.name);

  /// The parameter name.
  final String name;

  @override
  String toString() => '(param $name)';
}

/// A variable reference `$V{name}`.
final class VariableRefExpr extends Expr {
  /// Creates a variable reference node.
  const VariableRefExpr(this.name);

  /// The variable name.
  final String name;

  @override
  String toString() => '(var $name)';
}

/// A unary operation.
final class UnaryExpr extends Expr {
  /// Creates a unary node.
  const UnaryExpr(this.op, this.operand);

  /// The operator.
  final UnaryOp op;

  /// The operand.
  final Expr operand;

  @override
  String toString() => '(${_unarySymbol(op)} $operand)';
}

/// A binary operation.
final class BinaryExpr extends Expr {
  /// Creates a binary node.
  const BinaryExpr(this.op, this.left, this.right);

  /// The operator.
  final BinaryOp op;

  /// The left operand.
  final Expr left;

  /// The right operand.
  final Expr right;

  @override
  String toString() => '(${_binarySymbol(op)} $left $right)';
}

/// A conditional `cond ? then : otherwise`.
final class ConditionalExpr extends Expr {
  /// Creates a conditional node.
  const ConditionalExpr(this.condition, this.thenBranch, this.elseBranch);

  /// The boolean condition.
  final Expr condition;

  /// The value when the condition is true.
  final Expr thenBranch;

  /// The value when the condition is false.
  final Expr elseBranch;

  @override
  String toString() => '(if $condition $thenBranch $elseBranch)';
}

/// A function call `NAME(args...)`.
final class CallExpr extends Expr {
  /// Creates a call node.
  const CallExpr(this.name, this.arguments);

  /// The function name.
  final String name;

  /// The argument expressions.
  final List<Expr> arguments;

  @override
  String toString() => '(call $name${arguments.map((Expr a) => ' $a').join()})';
}

String _unarySymbol(UnaryOp op) => switch (op) {
      UnaryOp.negate => '-',
      UnaryOp.not => '!',
    };

String _binarySymbol(BinaryOp op) => switch (op) {
      BinaryOp.add => '+',
      BinaryOp.subtract => '-',
      BinaryOp.multiply => '*',
      BinaryOp.divide => '/',
      BinaryOp.modulo => '%',
      BinaryOp.equal => '==',
      BinaryOp.notEqual => '!=',
      BinaryOp.less => '<',
      BinaryOp.lessEqual => '<=',
      BinaryOp.greater => '>',
      BinaryOp.greaterEqual => '>=',
      BinaryOp.and => '&&',
      BinaryOp.or => '||',
    };
