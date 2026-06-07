/// Thrown when an expression string cannot be lexed or parsed (spec 005a).
///
/// A *structural* fault (malformed syntax), thrown at compile time — distinct
/// from a runtime evaluation failure, which is a [JetError] value rather than an
/// exception. Mirrors the domain's `ReportFormatException` policy.
library;

/// Signals a malformed expression (lex or parse error).
class ExpressionException implements Exception {
  /// Creates an exception describing why the expression is malformed.
  const ExpressionException(this.message);

  /// Human-readable description of the fault.
  final String message;

  @override
  String toString() => 'ExpressionException: $message';
}
