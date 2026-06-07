/// Renders a [ShapeElement] (spec 007a): a rectangle fills its box as a
/// [RectPrimitive]; a line draws across the box diagonal as a [LinePrimitive].
library;

import '../../../domain/elements/shape_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/styles/color.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../element_renderer.dart';
import '../render_context.dart';

/// The built-in renderer for `shape` elements.
class ShapeElementRenderer extends ElementRenderer<ShapeElement> {
  /// Const constructor.
  const ShapeElementRenderer();

  @override
  JetSize measure(ShapeElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(ShapeElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    switch (el.kind) {
      case ShapeKind.rectangle:
        out.add(RectPrimitive(
          bounds: bounds,
          fill: el.style.fill,
          stroke: el.style.stroke,
          strokeWidth: el.style.strokeWidth,
          elementId: el.id,
        ));
      case ShapeKind.line:
        final double left = bounds.x;
        final double top = bounds.y;
        final double right = bounds.x + bounds.width;
        final double bottom = bounds.y + bounds.height;
        final JetOffset start = el.flipDiagonal
            ? JetOffset(left, bottom)
            : JetOffset(left, top);
        final JetOffset end =
            el.flipDiagonal ? JetOffset(right, top) : JetOffset(right, bottom);
        out.add(LinePrimitive(
          bounds: bounds,
          start: start,
          end: end,
          color: el.style.stroke ?? JetColor.black,
          strokeWidth: el.style.strokeWidth,
          elementId: el.id,
        ));
    }
  }
}
