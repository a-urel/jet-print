/// An image element.
library;

import '../bool_property.dart';
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
    super.visible,
  });

  /// Where the image comes from.
  final JetImageSource source;

  /// How the image is scaled into [bounds].
  final JetBoxFit fit;

  @override
  String get typeKey => 'image';

  @override
  ImageElement withBounds(JetRect bounds) => ImageElement(
      id: id,
      bounds: bounds,
      source: source,
      fit: fit,
      name: name,
      visible: visible);

  @override
  ImageElement withName(String? name) => ImageElement(
      id: id,
      bounds: bounds,
      source: source,
      fit: fit,
      name: name,
      visible: visible);

  @override
  ImageElement withVisible(BoolProperty visible) => ImageElement(
      id: id,
      bounds: bounds,
      source: source,
      fit: fit,
      name: name,
      visible: visible);

  @override
  bool operator ==(Object other) =>
      other is ImageElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.source == source &&
      other.fit == fit &&
      other.name == name &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(id, bounds, source, fit, name, visible);

  @override
  String toString() => 'ImageElement($id, ${fit.name})';
}
