/// Thrown when a serialized report is structurally invalid.
library;

/// A structural fault encountered while decoding a report (missing
/// `schemaVersion`, a too-new schema, a malformed shape, …). Distinct from the
/// engine's non-fatal diagnostics: this is a fail-fast condition because the
/// input cannot be interpreted at all.
class ReportFormatException implements Exception {
  /// Creates the exception with a human-readable [message].
  const ReportFormatException(this.message);

  /// Describes what was wrong with the input.
  final String message;

  @override
  String toString() => 'ReportFormatException: $message';
}
