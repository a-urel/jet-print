/// The value-field template compiler (013) — a pure, bidirectional projection
/// between the designer's single value field and `TextElement.expression`.
///
/// The value field recognizes three forms (see [parseValueField]):
///   * literal text (with a `\` escape for literal brackets/braces),
///   * a whole-value `[fieldName]` simple field binding, and
///   * a `{ … }` advanced template mixing `[field]` tokens, literal text, and
///     function calls — e.g. `{upper[name]}`, `{[firstName] [lastName]}`.
///
/// Bindings stay single-sourced in `TextElement.expression`: a template compiles
/// to a canonical **expression string** the existing parser already accepts, and
/// [reverseCompile] turns a stored expression back into its display token so the
/// value field and canvas show the same thing. This is a presentation layer; it
/// adds no evaluation code and no parallel render path (Constitution IV).
library;

import '../../expression/aggregate/aggregate_functions.dart';
import '../../expression/ast.dart';
import '../../expression/expression_exception.dart';
import '../../expression/lexer.dart';
import '../../expression/parser.dart';
import '../../expression/value.dart';

/// The outcome of parsing the single value field's text.
sealed class ValueParse {
  const ValueParse();
}

/// The value is literal text (no binding).
final class LiteralValue extends ValueParse {
  /// Creates a literal result.
  const LiteralValue(this.text);

  /// The literal (already unescaped) text.
  final String text;

  @override
  bool operator ==(Object other) => other is LiteralValue && other.text == text;

  @override
  int get hashCode => Object.hash(LiteralValue, text);

  @override
  String toString() => 'LiteralValue("$text")';
}

/// The value is a binding compiled to an expression [expression].
final class BindingValue extends ValueParse {
  /// Creates a binding result.
  const BindingValue(this.expression);

  /// The compiled expression string (stored in `TextElement.expression`).
  final String expression;

  @override
  bool operator ==(Object other) =>
      other is BindingValue && other.expression == expression;

  @override
  int get hashCode => Object.hash(BindingValue, expression);

  @override
  String toString() => 'BindingValue("$expression")';
}

/// The display form of a stored binding, for the value field and canvas token.
final class ValueDisplay {
  /// Creates a display token. [editable] is false when the underlying
  /// expression is outside the template grammar (legacy/exotic): it is shown
  /// verbatim and read-only, never silently lost.
  const ValueDisplay(this.text, {this.editable = true});

  /// The token text — `[field]`, `{ … }`, or `{ rawExpression }` (read-only).
  final String text;

  /// Whether the value field may edit this as a template.
  final bool editable;

  @override
  bool operator ==(Object other) =>
      other is ValueDisplay && other.text == text && other.editable == editable;

  @override
  int get hashCode => Object.hash(text, editable);

  @override
  String toString() => 'ValueDisplay("$text", editable: $editable)';
}

/// Simple field token: the entire value is `[name]` with no nested
/// brackets/braces/backslash. The inner name is trimmed.
final RegExp _simpleField = RegExp(r'^\[([^\[\]{}\\]+)\]$');

/// Parses the value field's [raw] text into a literal or a binding.
ValueParse parseValueField(String raw) {
  if (raw.isEmpty) return const LiteralValue('');

  final RegExpMatch? simple = _simpleField.firstMatch(raw);
  if (simple != null) {
    return BindingValue('\$F{${simple.group(1)!.trim()}}');
  }

  if (raw.length >= 2 && raw.startsWith('{') && raw.endsWith('}')) {
    try {
      final String expr = _compileTemplate(raw.substring(1, raw.length - 1));
      Parser(tokenize(expr))
          .parseExpression(); // validate (malformed → literal)
      return BindingValue(expr);
    } on _TemplateError {
      // Malformed template → treat the whole value as literal.
    } on ExpressionException {
      // Malformed compiled expression → treat whole value as literal.
    }
  }

  return LiteralValue(_unescape(raw));
}

/// Turns a stored [expression] into its display token for the value field/canvas.
ValueDisplay reverseCompile(String expression) {
  final Expr root;
  try {
    root = Parser(tokenize(expression)).parseExpression();
  } on ExpressionException {
    return ValueDisplay('{$expression}', editable: false);
  }
  final String? token = _exprToToken(root);
  if (token == null) return ValueDisplay('{$expression}', editable: false);
  return ValueDisplay(token);
}

// ── template → expression ────────────────────────────────────────────────────

/// Thrown internally when a `{ … }` body is not a well-formed template, so the
/// caller can fall back to treating the value as literal.
class _TemplateError implements Exception {
  const _TemplateError();
}

String _compileTemplate(String inner) {
  final List<String> parts = <String>[];
  final StringBuffer literal = StringBuffer();

  void flushLiteral() {
    if (literal.isNotEmpty) {
      parts.add(_quote(literal.toString()));
      literal.clear();
    }
  }

  int i = 0;
  while (i < inner.length) {
    final String c = inner[i];
    if (c == r'\') {
      // Escape: the next char is literal.
      i++;
      literal.write(i < inner.length ? inner[i] : r'\');
      i++;
    } else if (c == '[') {
      flushLiteral();
      final _FieldScan scan = _scanField(inner, i);
      parts.add('\$F{${scan.name}}');
      i = scan.next;
    } else if (_isAlpha(c)) {
      final int identEnd = _scanIdentEnd(inner, i);
      if (identEnd < inner.length &&
          inner[identEnd] == '(' &&
          aggregateCalculationFor(inner.substring(i, identEnd)) != null) {
        // Inline aggregate: FN( <expr with [field] tokens> ).
        flushLiteral();
        final String fn = inner.substring(i, identEnd).toUpperCase();
        final _CallScan scan = _scanBalancedParens(inner, identEnd);
        parts.add('$fn(${_compileArg(scan.body)})');
        i = scan.next;
      } else if (identEnd < inner.length && inner[identEnd] == '[') {
        // Function sugar: ident[field].
        flushLiteral();
        final String fn = inner.substring(i, identEnd).toUpperCase();
        final _FieldScan scan = _scanField(inner, identEnd);
        parts.add('$fn(\$F{${scan.name}})');
        i = scan.next;
      } else {
        literal.write(inner.substring(i, identEnd));
        i = identEnd;
      }
    } else if (c == ']' || c == '{' || c == '}') {
      // A structural bracket/brace with no opener → malformed.
      throw const _TemplateError();
    } else {
      literal.write(c);
      i++;
    }
  }
  flushLiteral();

  if (parts.isEmpty) throw const _TemplateError();
  if (parts.length == 1 && !_isQuoted(parts.first)) return parts.first;
  return 'CONCAT(${parts.join(', ')})';
}

class _FieldScan {
  const _FieldScan(this.name, this.next);
  final String name;
  final int next;
}

/// Scans `[name]` starting at the `[` at [open]; returns the trimmed name and
/// the index just past the closing `]`.
_FieldScan _scanField(String s, int open) {
  final int close = s.indexOf(']', open + 1);
  if (close < 0) throw const _TemplateError();
  final String name = s.substring(open + 1, close).trim();
  if (name.isEmpty || name.contains('[') || name.contains('{')) {
    throw const _TemplateError();
  }
  return _FieldScan(name, close + 1);
}

int _scanIdentEnd(String s, int start) {
  int i = start;
  while (i < s.length && _isAlphaNumeric(s[i])) {
    i++;
  }
  return i;
}

class _CallScan {
  const _CallScan(this.body, this.next);
  final String body; // text between the outer parens
  final int next; // index just past the closing ')'
}

/// Scans `( … )` starting at the `(` at [open], honoring nested parens; returns
/// the inner text and the index past the matching `)`.
_CallScan _scanBalancedParens(String s, int open) {
  int depth = 0;
  for (int i = open; i < s.length; i++) {
    if (s[i] == '(') {
      depth++;
    } else if (s[i] == ')') {
      depth--;
      if (depth == 0) return _CallScan(s.substring(open + 1, i), i + 1);
    }
  }
  throw const _TemplateError();
}

/// Compiles an aggregate argument: replaces each `[name]` token with `$F{name}`
/// and passes all other expression syntax through unchanged.
String _compileArg(String arg) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < arg.length) {
    if (arg[i] == '[') {
      final _FieldScan scan = _scanField(arg, i);
      out.write('\$F{${scan.name}}');
      i = scan.next;
    } else {
      out.write(arg[i]);
      i++;
    }
  }
  return out.toString();
}

// ── expression → template token ──────────────────────────────────────────────

/// Renders [root] as a display token, or null if it is outside the grammar.
String? _exprToToken(Expr root) {
  if (root is FieldRefExpr) return '[${root.name}]';
  final AggregateCall? agg = topLevelAggregate(root);
  if (agg != null) {
    final String? arg = _argToToken(agg.argument);
    final String? fn = aggregateNameFor(agg.calculation);
    if (arg != null && fn != null) return '{$fn($arg)}';
  }
  if (root is CallExpr && root.name == 'CONCAT') {
    final String? body = _partsToToken(root.arguments);
    return body == null ? null : '{$body}';
  }
  // A single function-of-field call, e.g. UPPER($F{name}) → {upper[name]}.
  final String? part = _partToken(root);
  if (part != null && root is CallExpr) return '{$part}';
  return null;
}

String? _partsToToken(List<Expr> args) {
  final StringBuffer out = StringBuffer();
  for (final Expr arg in args) {
    final String? part = _partToken(arg);
    if (part == null) return null;
    out.write(part);
  }
  return out.toString();
}

/// A single template fragment for [e], or null if unsupported.
String? _partToken(Expr e) {
  if (e is FieldRefExpr) return '[${e.name}]';
  if (e is LiteralExpr) {
    final JetValue v = e.value;
    return v is JetString ? _escapeTemplateLiteral(v.value) : null;
  }
  if (e is CallExpr &&
      e.arguments.length == 1 &&
      e.arguments.single is FieldRefExpr) {
    final String field = (e.arguments.single as FieldRefExpr).name;
    return '${e.name.toLowerCase()}[$field]';
  }
  return null;
}

/// Renders an aggregate-argument [Expr] back to `[field]`-token template text,
/// or null if it contains a construct outside the round-trippable grammar.
String? _argToToken(Expr e) {
  if (e is FieldRefExpr) return '[${e.name}]';
  if (e is ParamRefExpr) return '\$P{${e.name}}';
  if (e is VariableRefExpr) return '\$V{${e.name}}';
  if (e is LiteralExpr) {
    final JetValue v = e.value;
    if (v is JetNumber) return _formatArgNumber(v.value);
    if (v is JetString) return '"${v.value.replaceAll('"', r'\"')}"';
    if (v is JetBool) return v.value ? 'true' : 'false';
    return null;
  }
  if (e is UnaryExpr) {
    final String? operand = _argToToken(e.operand);
    if (operand == null) return null;
    return '${e.op == UnaryOp.negate ? '-' : '!'}$operand';
  }
  if (e is BinaryExpr) {
    final String? l = _argOperand(e.left);
    final String? r = _argOperand(e.right);
    final String? op = _binarySymbol(e.op);
    if (l == null || r == null || op == null) return null;
    return '$l $op $r';
  }
  if (e is CallExpr) {
    final List<String> args = <String>[];
    for (final Expr a in e.arguments) {
      final String? t = _argToToken(a);
      if (t == null) return null;
      args.add(t);
    }
    return '${e.name.toLowerCase()}(${args.join(', ')})';
  }
  return null;
}

/// Renders [e] as a binary operand, wrapping a nested binary in parens so the
/// reversed token re-parses to the same tree (the forward `_compileArg` passes
/// author-written parens through, so a parenthesized operand is reachable).
String? _argOperand(Expr e) {
  final String? t = _argToToken(e);
  if (t == null) return null;
  return e is BinaryExpr ? '($t)' : t;
}

// Mirrors ast.dart's private _binarySymbol — keep the two in sync.
/// Binary operator → source symbol for argument round-tripping.
String? _binarySymbol(BinaryOp op) => switch (op) {
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

/// Renders a numeric literal without a trailing `.0` for integers.
String _formatArgNumber(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

// ── escaping helpers ─────────────────────────────────────────────────────────

/// Wraps [text] as a double-quoted expression string literal.
String _quote(String text) {
  final String body = text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$body"';
}

bool _isQuoted(String part) => part.startsWith('"');

/// Escapes the template-structural chars so a reverse-compiled literal run
/// re-parses to the same text.
String _escapeTemplateLiteral(String s) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final String c = s[i];
    if (c == r'\' || c == '[' || c == ']' || c == '{' || c == '}') {
      out.write(r'\');
    }
    out.write(c);
  }
  return out.toString();
}

/// Removes one level of backslash escaping from literal value-field text.
String _unescape(String raw) {
  if (!raw.contains(r'\')) return raw;
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < raw.length) {
    if (raw[i] == r'\' && i + 1 < raw.length) {
      out.write(raw[i + 1]);
      i += 2;
    } else {
      out.write(raw[i]);
      i++;
    }
  }
  return out.toString();
}

bool _isAlpha(String c) {
  if (c.isEmpty) return false;
  final int u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || c == '_';
}

bool _isAlphaNumeric(String c) {
  if (c.isEmpty) return false;
  final int u = c.codeUnitAt(0);
  return _isAlpha(c) || (u >= 0x30 && u <= 0x39);
}
