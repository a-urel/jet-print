/// The base type for everything placed on a band.
library;

import 'geometry.dart';

/// An immutable element definition positioned at absolute [bounds] within its
/// band. Concrete subtypes (text, image, line, barcode, …) add their own fields
/// and a stable [typeKey] used for serialization dispatch.
abstract class ReportElement {
  /// Creates an element with a unique [id] and absolute [bounds], and an
  /// optional human-facing [name].
  const ReportElement({required this.id, required this.bounds, this.name});

  /// Stable, unique identifier within a template (used for selection/binding).
  final String id;

  /// Absolute position and size within the owning band, in points.
  final JetRect bounds;

  /// Optional human-facing display name. When null/blank the UI shows a
  /// fallback (the element's text, or its type label). Never referenced by
  /// expressions; purely a label. Unconstrained — may be empty or duplicated.
  final String? name;

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

  /// Returns a copy of this element of the **same concrete type** with its
  /// display [name] replaced (pass `null` to clear), every other field
  /// preserved. The polymorphic rename primitive (mirrors [withBounds]). An
  /// [UnknownElement] is a no-op passthrough (its preserved JSON is inert).
  ReportElement withName(String? name);
}
