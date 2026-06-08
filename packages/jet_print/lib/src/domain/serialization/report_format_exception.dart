/// Thrown when a report definition is structurally invalid.
library;

/// A structural fault in a report definition — either while decoding (missing
/// `schemaVersion`, a too-new schema, a malformed shape, …) or during fill
/// validation (e.g. duplicate group names, spec 007c). Distinct from the
/// engine's non-fatal diagnostics: this is a fail-fast condition because the
/// definition cannot be interpreted at all.
class ReportFormatException implements Exception {
  /// Creates the exception with a human-readable [message].
  const ReportFormatException(this.message);

  /// Describes what was wrong with the input.
  final String message;

  @override
  String toString() => 'ReportFormatException: $message';
}
