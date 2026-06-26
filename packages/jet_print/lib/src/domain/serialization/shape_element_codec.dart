/// JSON codec for [ShapeElement].
library;

import '../bool_property.dart';
import '../elements/shape_element.dart';
import '../geometry.dart';
import '../styles/box_style.dart';
import 'element_codec.dart';

/// Serializes [ShapeElement] to/from its field map.
class ShapeElementCodec extends ElementCodec<ShapeElement> {
  /// Const constructor (the codec is stateless).
  const ShapeElementCodec();

  @override
  ShapeElement fromJson(Map<String, Object?> json) {
    // Tolerant parse (020 / FR-009): an unrecognized form — e.g. one a NEWER
    // version added — loads as a rectangle (a safe render default) while the
    // original name is preserved in `unknownForm`, so re-saving does not lose
    // it. Known forms resolve exactly as before.
    final String raw = json['kind']! as String;
    final ShapeKind? known = ShapeKind.values.asNameMap()[raw];
    return ShapeElement(
      id: json['id']! as String,
      bounds:
          JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
      kind: known ?? ShapeKind.rectangle,
      style: json['style'] is Map
          ? JetBoxStyle.fromJson(
              (json['style']! as Map).cast<String, Object?>())
          : JetBoxStyle.none,
      flipDiagonal: (json['flipDiagonal'] as bool?) ?? false,
      unknownForm: known == null ? raw : null,
      name: json['name'] as String?,
      visible: json['visible'] is Map
          ? BoolProperty.fromJson(
              (json['visible']! as Map).cast<String, Object?>())
          : const BoolProperty(),
    );
  }

  @override
  Map<String, Object?> toJson(ShapeElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        // Write the preserved unrecognized name back when present, else the
        // known form's name — a lossless forward-compatible round-trip.
        'kind': element.unknownForm ?? element.kind.name,
        if (element.style != JetBoxStyle.none) 'style': element.style.toJson(),
        if (element.flipDiagonal) 'flipDiagonal': true,
        if (element.name != null) 'name': element.name,
        if (element.visible != const BoolProperty())
          'visible': element.visible.toJson(),
      };
}
