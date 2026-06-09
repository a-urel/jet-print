/// The base type for everything placed on a band.
library;

import 'geometry.dart';

/// An immutable element definition positioned at absolute [bounds] within its
/// band. Concrete subtypes (text, image, line, barcode, …) add their own fields
/// and a stable [typeKey] used for serialization dispatch.
abstract class ReportElement {
  /// Creates an element with a unique [id] and absolute [bounds].
  const ReportElement({required this.id, required this.bounds});

  /// Stable, unique identifier within a template (used for selection/binding).
  final String id;

  /// Absolute position and size within the owning band, in points.
  final JetRect bounds;

  /// Stable string key identifying this element's type for serialization.
  /// Must be unique per registered type (see `ElementCodecRegistry`).
  String get typeKey;

  /// Returns a copy of this element of the **same concrete type** repositioned
  /// (and/or resized) to [bounds], with every other field preserved.
  ///
  /// This is the polymorphic move/resize primitive the designer edits through
  /// (FR-008/FR-009/FR-025): editing one element never disturbs another. An
  /// [UnknownElement] is intentionally a no-op passthrough — its preserved JSON
  /// is never rewritten (Constitution V).
  ReportElement withBounds(JetRect bounds);
}
