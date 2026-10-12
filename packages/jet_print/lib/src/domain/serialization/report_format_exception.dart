/// Thrown when a report definition is structurally invalid.
library;

/// A structural fault found while decoding a report definition (missing
/// `schemaVersion`, a too-new schema, a malformed shape, an unknown enum name,
/// …). Distinct from the engine's non-fatal diagnostics: this is a fail-fast
/// condition because the definition cannot be interpreted at all.
class ReportFormatException implements Exception {
  /// Creates the exception with a human-readable [message].
  const ReportFormatException(this.message);

  /// Describes what was wrong with the input.
  final String message;

  @override
  String toString() => 'ReportFormatException: $message';
}
