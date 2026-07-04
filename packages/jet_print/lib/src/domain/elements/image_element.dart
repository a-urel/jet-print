/// An image element.
library;

import '../bool_property.dart';
import '../copy_support.dart';
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

  /// Returns a copy with the named fields replaced and the rest preserved.
  ///
  /// [name] is nullable, so it takes a thunk: omit to preserve, pass
  /// `() => value` to replace (`() => null` clears).
  ImageElement copyWith({
    JetRect? bounds,
    JetImageSource? source,
    JetBoxFit? fit,
    String? Function()? name,
    BoolProperty? visible,
  }) =>
      ImageElement(
        id: id,
        bounds: bounds ?? this.bounds,
        source: source ?? this.source,
        fit: fit ?? this.fit,
        name: pick(name, this.name),
        visible: visible ?? this.visible,
      );

  @override
  ImageElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  ImageElement withName(String? name) => copyWith(name: () => name);

  @override
  ImageElement withVisible(BoolProperty visible) => copyWith(visible: visible);

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
