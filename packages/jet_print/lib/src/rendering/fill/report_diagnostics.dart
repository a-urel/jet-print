/// Non-fatal issues collected while rendering (spec 007b; public since 011 —
/// FR-013). The engine never throws on a content problem — it records a
/// [Diagnostic] and continues (render-don't-crash), so a report always
/// produces a paintable result. Hosts read the merged collection from
/// `RenderedReport.diagnostics`: an unknown field, a missing parameter, an
/// expression-evaluation error, an empty dataset, or an unresolvable image
/// each yields a specific entry identifying the problem (and the offending
/// element, where applicable) next to a best-effort render (FR-014/SC-007).
library;

/// The severity of a [Diagnostic].
enum DiagnosticSeverity {
  /// Expected-but-noteworthy conditions (e.g. an empty dataset rendering the
  /// noData band).
  info,

  /// Likely authoring or data mistakes that still render with a fallback
  /// (e.g. an unknown field rendering blank, a URL-only image rendering a
  /// placeholder).
  warning,

  /// Evaluation failures rendered as a visible `!ERR` fallback (e.g. a type
  /// mismatch or divide-by-zero in an expression).
  error,
}

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

  /// Appends an already-constructed [diagnostic] — e.g. when merging several
  /// passes' diagnostics into one ordered collection (011).
  void add(Diagnostic diagnostic) => _entries.add(diagnostic);

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
