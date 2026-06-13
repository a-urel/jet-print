// ShapeElementRenderer: rectangle -> RectPrimitive; line -> diagonal
// LinePrimitive; every other form (020) -> one PathPrimitive from `shapePath`.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/shape_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/shape_path.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx = RenderContext(
      measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const ShapeElementRenderer renderer = ShapeElementRenderer();
  const JetRect bounds = JetRect(x: 10, y: 20, width: 40, height: 30);

  test('measure returns the authored box size', () {
    const ShapeElement el =
        ShapeElement(id: 'r', bounds: bounds, kind: ShapeKind.rectangle);
    expect(renderer.measure(el, ctx, const JetConstraints()),
        const JetSize(40, 30));
  });

  test('rectangle emits a RectPrimitive carrying the box style', () {
    const ShapeElement el = ShapeElement(
      id: 'r',
      bounds: bounds,
      kind: ShapeKind.rectangle,
      style: JetBoxStyle(
          fill: JetColor.black, stroke: JetColor.black, strokeWidth: 2),
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

  // 021 / C7 — stroke width 0 removes the outline at the ONE renderer seam
  // (`stroke: strokeWidth > 0 ? style.stroke : null`), zero painter changes;
  // the stored stroke color stays on the style so width > 0 restores it.
  group('stroke width 0 hides the outline (021 / C7)', () {
    const JetBoxStyle zeroWidth = JetBoxStyle(
      fill: JetColor(0x2200FF00),
      stroke: JetColor(0xFF112233),
      strokeWidth: 0,
    );

    test('rectangle emits stroke: null when width is 0, fill intact', () {
      const ShapeElement el = ShapeElement(
          id: 'r', bounds: bounds, kind: ShapeKind.rectangle, style: zeroWidth);
      final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
      renderer.emit(el, ctx, bounds, out);
      final RectPrimitive p = out.build().primitives.single as RectPrimitive;
      expect(p.stroke, isNull, reason: 'no outline at width 0');
      expect(p.fill, const JetColor(0x2200FF00), reason: 'fill unaffected');
      expect(el.style.stroke, const JetColor(0xFF112233),
          reason: 'the stored stroke color is retained on the style');
    });

    test('closed path forms emit stroke: null when width is 0', () {
      const ShapeElement el = ShapeElement(
          id: 'p', bounds: bounds, kind: ShapeKind.hexagon, style: zeroWidth);
      final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
      renderer.emit(el, ctx, bounds, out);
      final PathPrimitive p = out.build().primitives.single as PathPrimitive;
      expect(p.stroke, isNull);
      expect(p.fill, const JetColor(0x2200FF00));
    });

    test('a line with width 0 emits nothing (its stroke IS the shape)', () {
      const ShapeElement el = ShapeElement(
          id: 'l',
          bounds: bounds,
          kind: ShapeKind.line,
          style: JetBoxStyle(stroke: JetColor.black, strokeWidth: 0));
      final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
      renderer.emit(el, ctx, bounds, out);
      expect(out.build().primitives, isEmpty,
          reason: 'a zero-width LinePrimitive would still paint a hairline');
    });

    test('a negative width behaves like 0', () {
      const ShapeElement el = ShapeElement(
          id: 'r',
          bounds: bounds,
          kind: ShapeKind.rectangle,
          style: JetBoxStyle(stroke: JetColor.black, strokeWidth: -1));
      final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
      renderer.emit(el, ctx, bounds, out);
      expect((out.build().primitives.single as RectPrimitive).stroke, isNull);
    });

    test('width > 0 still carries the stroke (the 020 behavior, unchanged)',
        () {
      const ShapeElement el = ShapeElement(
          id: 'r',
          bounds: bounds,
          kind: ShapeKind.rectangle,
          style: JetBoxStyle(stroke: JetColor(0xFF112233), strokeWidth: 2));
      final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
      renderer.emit(el, ctx, bounds, out);
      expect((out.build().primitives.single as RectPrimitive).stroke,
          const JetColor(0xFF112233));
    });
  });

  // 020 / C7.1 — every form that is not line/rectangle renders as exactly one
  // PathPrimitive whose commands ARE `shapePath(kind, bounds)` and whose
  // fill/stroke/strokeWidth come straight from the element's style. This is the
  // single shared render path that makes canvas == preview == export.
  group('new forms emit one PathPrimitive from shapePath (020)', () {
    const List<ShapeKind> pathForms = <ShapeKind>[
      ShapeKind.ellipse,
      ShapeKind.triangle,
      ShapeKind.diamond,
      ShapeKind.pentagon,
      ShapeKind.hexagon,
      ShapeKind.star,
    ];

    for (final ShapeKind kind in pathForms) {
      test('${kind.name} -> a single PathPrimitive matching shapePath', () {
        final ShapeElement el = ShapeElement(
          id: 'p',
          bounds: bounds,
          kind: kind,
          style: const JetBoxStyle(
              fill: JetColor(0x22000000),
              stroke: JetColor.black,
              strokeWidth: 3),
        );
        final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
        renderer.emit(el, ctx, bounds, out);
        final PathPrimitive p = out.build().primitives.single as PathPrimitive;
        expect(p.commands, shapePath(kind, bounds));
        expect(p.bounds, bounds);
        expect(p.fill, const JetColor(0x22000000));
        expect(p.stroke, JetColor.black);
        expect(p.strokeWidth, 3);
        expect(p.elementId, 'p');
      });
    }
  });
}
