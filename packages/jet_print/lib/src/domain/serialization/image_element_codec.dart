/// JSON codec for [ImageElement].
library;

import '../bool_property.dart';
import '../elements/image_element.dart';
import '../elements/image_source.dart';
import '../geometry.dart';
import 'element_codec.dart';

/// Serializes [ImageElement] to/from its field map.
class ImageElementCodec extends ElementCodec<ImageElement> {
  /// Const constructor (the codec is stateless).
  const ImageElementCodec();

  @override
  ImageElement fromJson(Map<String, Object?> json) => ImageElement(
        id: json['id']! as String,
        bounds:
            JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        source: JetImageSource.fromJson(
            (json['source']! as Map).cast<String, Object?>()),
        fit: JetBoxFit.values.byName(json['fit']! as String),
        name: json['name'] as String?,
        visible: json['visible'] is Map
            ? BoolProperty.fromJson(
                (json['visible']! as Map).cast<String, Object?>())
            : const BoolProperty(),
      );

  @override
  Map<String, Object?> toJson(ImageElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'source': element.source.toJson(),
        'fit': element.fit.name,
        if (element.name != null) 'name': element.name,
        if (element.visible != const BoolProperty())
          'visible': element.visible.toJson(),
      };
}
