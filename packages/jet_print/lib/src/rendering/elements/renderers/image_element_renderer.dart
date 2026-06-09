/// Renders an [ImageElement] (spec 007a). Embedded [BytesImageSource] becomes an
/// [ImagePrimitive]; a not-yet-resolved url/field source renders a placeholder
/// (byte resolution for those sources is a 007b / paint-prep concern).
library;

import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/geometry.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// The built-in renderer for `image` elements.
class ImageElementRenderer extends ElementRenderer<ImageElement> {
  /// Const constructor.
  const ImageElementRenderer();

  @override
  JetSize measure(
          ImageElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(
      ImageElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    final JetImageSource source = el.source;
    if (source is BytesImageSource) {
      out.add(ImagePrimitive(
        bounds: bounds,
        bytes: source.bytes,
        fit: el.fit,
        elementId: el.id,
      ));
    } else {
      emitPlaceholder(out, bounds, 'image', ctx, elementId: el.id);
    }
  }
}
