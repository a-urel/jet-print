/// Lexical tokens for the expression language (spec 005a). Internal to the
/// expression seam — not part of the public API.
library;

/// The kind of a lexical [Token].
enum TokenType {
  /// A numeric literal, e.g. `5` or `2.5` (literal is a `double`).
  number,

  /// A string literal, e.g. `'hi'` (literal is a `String`).
  string,

  /// The keyword `true`.
  trueLiteral,

  /// The keyword `false`.
  falseLiteral,

  /// The keyword `null`.
  nullLiteral,

  /// A field reference `$F{name}` (literal is the field name `String`).
  fieldRef,

  /// A parameter reference `$P{name}` (literal is the param name `String`).
  paramRef,

  /// A bare identifier (a function name), e.g. `ROUND`.
  identifier,

  /// `+`
  plus,

  /// `-`
  minus,

  /// `*`
  star,

  /// `/`
  slash,

  /// `%`
  percent,

  /// `==`
  equalEqual,

  /// `!=`
  bangEqual,

  /// `<`
  less,

  /// `<=`
  lessEqual,

  /// `>`
  greater,

  /// `>=`
  greaterEqual,

  /// `&&`
  andAnd,

  /// `||`
  orOr,

  /// `!`
  bang,

  /// `?`
  question,

  /// `:`
  colon,

  /// `,`
  comma,

  /// `(`
  leftParen,

  /// `)`
  rightParen,

  /// End of input.
  eof,
}

/// A lexical token: its [type], source [lexeme], and an optional decoded
/// [literal] (a `double` for numbers, a `String` for strings/field/param refs).
class Token {
  /// Creates a token.
  const Token(this.type, this.lexeme, [this.literal]);

  /// The token kind.
  final TokenType type;

  /// The exact source text of the token.
  final String lexeme;

  /// The decoded literal value, if any (number → `double`; string/ref → name).
  final Object? literal;

  @override
  String toString() => 'Token(${type.name}, "$lexeme"'
      '${literal == null ? '' : ', $literal'})';
}
