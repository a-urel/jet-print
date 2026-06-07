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
}
