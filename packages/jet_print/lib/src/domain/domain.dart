/// Domain seam — the report model.
///
/// This is the innermost layer. Code here is pure Dart describing *what* a
/// report is, independent of how it is laid out or drawn.
///
/// Dependency rule (FR-007): the domain seam depends on **nothing inward** and
/// MUST NOT import the `rendering` or `designer` seams, nor any Flutter
/// widget/rendering library. The architecture test enforces this.
library;

/// A placeholder domain entity representing a report document.
///
/// This is pure Dart with no UI or rendering dependencies: it describes *what* a
/// report is, leaving layout and drawing to the outer seams. The fields are
/// intentionally minimal for the scaffold — the real report model is fleshed out
/// in a later iteration.
class ReportDocument {
  /// Creates a report document with the given [title] and optional [sections].
  const ReportDocument({
    required this.title,
    this.sections = const <String>[],
  });

  /// Human-readable title of the report.
  final String title;

  /// Ordered names of the report's sections.
  final List<String> sections;

  /// Whether the document has no sections yet.
  bool get isEmpty => sections.isEmpty;
}
