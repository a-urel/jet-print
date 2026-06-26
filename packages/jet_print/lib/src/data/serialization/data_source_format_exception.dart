/// Thrown when a `*.jetreport.datasource` document is structurally invalid.
library;

/// A structural fault while decoding a data-source file — a missing/too-new
/// `jetDataSource` version, a malformed shape, or an unknown field type. A
/// fail-fast condition: the document cannot be interpreted at all. Parallel to
/// `ReportFormatException` for the report-definition format.
class JetDataSourceFormatException implements Exception {
  /// Creates the exception with a human-readable [message].
  const JetDataSourceFormatException(this.message);

  /// Describes what was wrong with the input.
  final String message;

  @override
  String toString() => 'JetDataSourceFormatException: $message';
}
