/// JSON codec for [ShapeElement].
library;

import '../elements/shape_element.dart';
import '../geometry.dart';
import '../styles/box_style.dart';
import 'element_codec.dart';

/// Serializes [ShapeElement] to/from its field map.
class ShapeElementCodec extends ElementCodec<ShapeElement> {
  /// Const constructor (the codec is stateless).
  const ShapeElementCodec();

  @override
  ShapeElement fromJson(Map<String, Object?> json) => ShapeElement(
        id: json['id']! as String,
        bounds:
            JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        kind: ShapeKind.values.byName(json['kind']! as String),
        style: json['style'] is Map
            ? JetBoxStyle.fromJson(
                (json['style']! as Map).cast<String, Object?>())
            : JetBoxStyle.none,
        flipDiagonal: (json['flipDiagonal'] as bool?) ?? false,
      );

  @override
  Map<String, Object?> toJson(ShapeElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'kind': element.kind.name,
        if (element.style != JetBoxStyle.none) 'style': element.style.toJson(),
        if (element.flipDiagonal) 'flipDiagonal': true,
      };
}
