/// An image element.
library;

import '../report_element.dart';
import 'image_source.dart';

/// Draws an image from [source], scaled to [bounds] per [fit].
class ImageElement extends ReportElement {
  /// Creates an image element.
  const ImageElement({
    required super.id,
    required super.bounds,
    required this.source,
    this.fit = JetBoxFit.contain,
  });

  /// Where the image comes from.
  final JetImageSource source;

  /// How the image is scaled into [bounds].
  final JetBoxFit fit;

  @override
  String get typeKey => 'image';

  @override
  bool operator ==(Object other) =>
      other is ImageElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.source == source &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(id, bounds, source, fit);

  @override
  String toString() => 'ImageElement($id, ${fit.name})';
}
