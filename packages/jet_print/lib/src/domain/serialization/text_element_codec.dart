/// JSON codec for [TextElement].
library;

import '../elements/text_element.dart';
import '../geometry.dart';
import 'element_codec.dart';

/// Serializes [TextElement] to/from its field map.
class TextElementCodec extends ElementCodec<TextElement> {
  /// Const constructor (the codec is stateless).
  const TextElementCodec();

  @override
  TextElement fromJson(Map<String, Object?> json) => TextElement(
        id: json['id']! as String,
        bounds:
            JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        text: json['text']! as String,
      );

  @override
  Map<String, Object?> toJson(TextElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'text': element.text,
      };
}
