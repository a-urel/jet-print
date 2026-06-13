/// Renders a [ShapeElement] (spec 007a, extended in 020): a rectangle fills its
/// box as a [RectPrimitive]; a line draws across the box diagonal as a
/// [LinePrimitive]; every other form draws as a single [PathPrimitive] built
/// from the shared `shapePath` geometry, so canvas, preview, and export agree.
library;

import '../../../domain/elements/shape_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/styles/color.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../element_renderer.dart';
import '../render_context.dart';
import '../shape_path.dart';

/// The built-in renderer for `shape` elements.
class ShapeElementRenderer extends ElementRenderer<ShapeElement> {
  /// Const constructor.
  const ShapeElementRenderer();

  @override
  JetSize measure(
          ShapeElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(
      ShapeElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    // The ONE stroke-width-0 seam (021 / C7, research §6): at width 0 the
    // outline is not emitted on any path, while the stored stroke color stays
    // on the style so stepping the width back restores it. Handled here once —
    // zero painter changes, parity across canvas/preview/export.
    final JetColor? stroke =
        el.style.strokeWidth > 0 ? el.style.stroke : null;
    switch (el.kind) {
      case ShapeKind.rectangle:
        out.add(RectPrimitive(
          bounds: bounds,
          fill: el.style.fill,
          stroke: stroke,
          strokeWidth: el.style.strokeWidth,
          elementId: el.id,
        ));
      case ShapeKind.line:
        // A line's stroke IS the shape: a zero-width LinePrimitive would
        // still paint a hairline in both backends, so emit nothing. A stroke
        // with no color keeps its default-black design-time render (020).
        if (el.style.strokeWidth <= 0) return;
        final double left = bounds.x;
        final double top = bounds.y;
        final double right = bounds.x + bounds.width;
        final double bottom = bounds.y + bounds.height;
        final JetOffset start =
            el.flipDiagonal ? JetOffset(left, bottom) : JetOffset(left, top);
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
      // Every closed form (020) shares one render path: a PathPrimitive built
      // from `shapePath`, replayed identically by the canvas and PDF painters.
      case ShapeKind.ellipse:
      case ShapeKind.triangle:
      case ShapeKind.diamond:
      case ShapeKind.pentagon:
      case ShapeKind.hexagon:
      case ShapeKind.star:
        out.add(PathPrimitive(
          bounds: bounds,
          commands: shapePath(el.kind, bounds),
          fill: el.style.fill,
          stroke: stroke,
          strokeWidth: el.style.strokeWidth,
          elementId: el.id,
        ));
    }
  }
}
