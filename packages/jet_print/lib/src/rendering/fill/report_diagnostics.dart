/// Non-fatal issues collected during Fill (spec 007b). The data pass never throws
/// on a content problem — it records a [Diagnostic] and continues (render-don't-
/// crash), so a report always produces a paintable result.
library;

/// The severity of a [Diagnostic].
enum DiagnosticSeverity { info, warning, error }

/// One collected issue, optionally tagged with the originating [elementId].
class Diagnostic {
  /// Creates a diagnostic.
  const Diagnostic(this.severity, this.message, {this.elementId});

  /// How serious the issue is.
  final DiagnosticSeverity severity;

  /// A human-readable description.
  final String message;

  /// The originating element's id, or null.
  final String? elementId;

  @override
  String toString() =>
      '${severity.name.toUpperCase()}: $message${elementId == null ? '' : ' [$elementId]'}';
}

/// A growable collection of [Diagnostic]s with severity helpers.
class ReportDiagnostics {
  final List<Diagnostic> _entries = <Diagnostic>[];

  /// The collected diagnostics in insertion order (unmodifiable view).
  List<Diagnostic> get entries => List<Diagnostic>.unmodifiable(_entries);

  /// Records an informational diagnostic.
  void info(String message, {String? elementId}) => _entries
      .add(Diagnostic(DiagnosticSeverity.info, message, elementId: elementId));

  /// Records a warning diagnostic.
  void warning(String message, {String? elementId}) => _entries.add(
      Diagnostic(DiagnosticSeverity.warning, message, elementId: elementId));

  /// Records an error diagnostic.
  void error(String message, {String? elementId}) => _entries
      .add(Diagnostic(DiagnosticSeverity.error, message, elementId: elementId));

  /// Whether any error-severity diagnostic was recorded.
  bool get hasErrors =>
      _entries.any((Diagnostic d) => d.severity == DiagnosticSeverity.error);
}
