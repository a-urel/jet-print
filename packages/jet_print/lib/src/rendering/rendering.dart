/// Rendering seam — layout and rendering.
///
/// This layer turns domain models into laid-out, drawable structures.
///
/// Dependency rule (FR-007): the rendering seam may depend on the `domain`
/// seam **only**. It MUST NOT import the `designer` seam. Dependencies point
/// inward toward `domain`.
library;

import '../domain/domain.dart';

/// A placeholder rendering entity that lays out a [ReportDocument].
///
/// It depends on the domain seam only, demonstrating the inward dependency
/// direction. The layout logic is a stand-in: one page per section, and at least
/// one page for an empty document.
class ReportLayout {
  /// Creates a layout for the given [document].
  const ReportLayout(this.document);

  /// The domain document this layout is derived from.
  final ReportDocument document;

  /// Number of pages this layout produces.
  int get pageCount => document.sections.isEmpty ? 1 : document.sections.length;
}
