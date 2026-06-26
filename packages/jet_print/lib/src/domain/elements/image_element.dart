/// An image element.
library;

import '../geometry.dart';
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
    super.name,
  });

  /// Where the image comes from.
  final JetImageSource source;

  /// How the image is scaled into [bounds].
  final JetBoxFit fit;

  @override
  String get typeKey => 'image';

  @override
  ImageElement withBounds(JetRect bounds) =>
      ImageElement(id: id, bounds: bounds, source: source, fit: fit, name: name);

  @override
  ImageElement withName(String? name) =>
      ImageElement(id: id, bounds: bounds, source: source, fit: fit, name: name);

  @override
  bool operator ==(Object other) =>
      other is ImageElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.source == source &&
      other.fit == fit &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, bounds, source, fit, name);

  @override
  String toString() => 'ImageElement($id, ${fit.name})';
}
