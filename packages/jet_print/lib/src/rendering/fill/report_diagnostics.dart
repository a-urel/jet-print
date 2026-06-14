/// Non-fatal issues collected while rendering (spec 007b; public since 011 —
/// FR-013). The engine never throws on a content problem — it records a
/// [Diagnostic] and continues (render-don't-crash), so a report always
/// produces a paintable result. Hosts read the merged collection from
/// `RenderedReport.diagnostics`: an unknown field, a missing parameter, an
/// expression-evaluation error, an empty dataset, or an unresolvable image
/// each yields a specific entry identifying the problem (and the offending
/// element, where applicable) next to a best-effort render (FR-014/SC-007).
///
/// [Diagnostic] and [DiagnosticSeverity] are pure value types and now live in
/// the domain layer ([Diagnostic] is also produced by author-time
/// `validate()`); they are re-exported here so existing importers and the
/// public API are unaffected.
library;

import '../../domain/diagnostic.dart';

export '../../domain/diagnostic.dart' show Diagnostic, DiagnosticSeverity;

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
