/// Renders a [TextElement] as one pre-broken [TextRunPrimitive] (spec 007a).
///
/// Wraps at the element's own authored width (`el.bounds.width`) in BOTH measure
/// and emit — a local determinism invariant that does not depend on the caller
/// passing a particular constraint or bounds width (text grows in height only).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/geometry.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../../text/text_measurer.dart';
import '../element_renderer.dart';
import '../render_context.dart';

/// The built-in renderer for `text` elements.
class TextElementRenderer extends ElementRenderer<TextElement> {
  /// Const constructor.
  const TextElementRenderer();

  @override
  JetSize measure(TextElement el, RenderContext ctx, JetConstraints constraints) =>
      ctx.measurer.measure(el.text, el.style, maxWidth: el.bounds.width).size;

  @override
  void emit(TextElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    final MeasuredText m =
        ctx.measurer.measure(el.text, el.style, maxWidth: el.bounds.width);
    out.add(TextRunPrimitive(
      bounds: bounds,
      lines: m.lines,
      style: el.style,
      fontFamily: m.fontFamily,
      elementId: el.id,
    ));
  }
}
