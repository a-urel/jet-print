/// A non-fatal issue — the shared value type for both render-time diagnostics
/// (spec 007b/011) and author-time validation (spec 024 `validate()`).
///
/// Pure domain value type (no rendering/Flutter deps), so it can be produced by
/// the innermost layer (`validate(ReportDefinition)`) and by the render chain
/// alike. The render engine records these and continues (render-don't-crash);
/// the designer surfaces validation ones before render.
library;

/// The severity of a [Diagnostic].
enum DiagnosticSeverity {
  /// Expected-but-noteworthy conditions (e.g. an empty dataset rendering the
  /// noData band; a representable-but-not-yet-rendered shape).
  info,

  /// Likely authoring or data mistakes that still render with a fallback
  /// (e.g. an unknown field rendering blank, a URL-only image rendering a
  /// placeholder).
  warning,

  /// Evaluation/validation failures (e.g. a type mismatch in an expression, or
  /// a violated structural invariant) — rendered as a visible `!ERR` fallback
  /// where applicable.
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
  bool operator ==(Object other) =>
      other is Diagnostic &&
      other.severity == severity &&
      other.message == message &&
      other.elementId == elementId;

  @override
  int get hashCode => Object.hash(severity, message, elementId);

  @override
  String toString() =>
      '${severity.name.toUpperCase()}: $message${elementId == null ? '' : ' [$elementId]'}';
}
