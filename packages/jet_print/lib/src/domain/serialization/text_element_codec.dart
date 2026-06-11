/// JSON codec for [TextElement].
library;

import '../elements/text_element.dart';
import '../geometry.dart';
import '../styles/text_style.dart';
import 'element_codec.dart';

/// Serializes [TextElement] to/from its field map. The `style` key is written
/// only when the style is non-default, preserving the compact wire shape for
/// unstyled text.
class TextElementCodec extends ElementCodec<TextElement> {
  /// Const constructor (the codec is stateless).
  const TextElementCodec();

  @override
  TextElement fromJson(Map<String, Object?> json) => TextElement(
        id: json['id']! as String,
        bounds:
            JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        text: json['text']! as String,
        style: json['style'] is Map
            ? JetTextStyle.fromJson(
                (json['style']! as Map).cast<String, Object?>())
            : JetTextStyle.fallback,
        expression: json['expression'] as String?,
        format: json['format'] as String?,
      );

  @override
  Map<String, Object?> toJson(TextElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'text': element.text,
        if (element.style != JetTextStyle.fallback)
          'style': element.style.toJson(),
        if (element.expression != null) 'expression': element.expression,
        if (element.format != null) 'format': element.format,
      };
}
