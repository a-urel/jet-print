// lib/src/rendering/text/font_format_exception.dart
/// Thrown when font bytes cannot be parsed (spec 006). Structural — fail fast.
library;

/// A malformed or unsupported font file.
class FontFormatException implements Exception {
  /// Creates the exception with a human-readable [message].
  const FontFormatException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'FontFormatException: $message';
}
