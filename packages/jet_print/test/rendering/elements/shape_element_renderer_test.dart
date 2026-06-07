// ShapeElementRenderer: rectangle -> RectPrimitive; line -> diagonal LinePrimitive.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/shape_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx =
      RenderContext(measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const ShapeElementRenderer renderer = ShapeElementRenderer();
  const JetRect bounds = JetRect(x: 10, y: 20, width: 40, height: 30);

  test('measure returns the authored box size', () {
    const ShapeElement el = ShapeElement(
        id: 'r', bounds: bounds, kind: ShapeKind.rectangle);
    expect(renderer.measure(el, ctx, const JetConstraints()),
        const JetSize(40, 30));
  });

  test('rectangle emits a RectPrimitive carrying the box style', () {
    const ShapeElement el = ShapeElement(
      id: 'r',
      bounds: bounds,
      kind: ShapeKind.rectangle,
      style: JetBoxStyle(fill: JetColor.black, stroke: JetColor.black, strokeWidth: 2),
    );
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final RectPrimitive p = out.build().primitives.single as RectPrimitive;
    expect(p.bounds, bounds);
    expect(p.fill, JetColor.black);
    expect(p.stroke, JetColor.black);
    expect(p.strokeWidth, 2);
    expect(p.elementId, 'r');
  });

  test('line emits the top-left -> bottom-right diagonal by default', () {
    const ShapeElement el =
        ShapeElement(id: 'l', bounds: bounds, kind: ShapeKind.line);
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final LinePrimitive p = out.build().primitives.single as LinePrimitive;
    expect(p.start, const JetOffset(10, 20));
    expect(p.end, const JetOffset(50, 50));
    expect(p.color, JetColor.black); // default when style has no stroke
    expect(p.elementId, 'l');
  });

  test('flipDiagonal line emits bottom-left -> top-right', () {
    const ShapeElement el = ShapeElement(
        id: 'l', bounds: bounds, kind: ShapeKind.line, flipDiagonal: true);
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final LinePrimitive p = out.build().primitives.single as LinePrimitive;
    expect(p.start, const JetOffset(10, 50));
    expect(p.end, const JetOffset(50, 20));
  });
}
