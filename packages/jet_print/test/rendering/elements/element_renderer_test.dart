// The render contract: RenderContext (measurer holder) + ElementRenderer<E>.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/element_renderer.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

/// A minimal concrete renderer proving the contract compiles and dispatches.
class _StubRenderer extends ElementRenderer<TextElement> {
  const _StubRenderer();
  @override
  JetSize measure(TextElement el, RenderContext ctx, JetConstraints c) =>
      JetSize(el.bounds.width, el.bounds.height);
  @override
  void emit(TextElement el, RenderContext ctx, JetRect bounds,
          FrameBuilder out) =>
      out.add(RectPrimitive(bounds: bounds, elementId: el.id));
}

void main() {
  final RenderContext ctx = RenderContext(
      measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));

  test('RenderContext exposes its measurer', () {
    expect(ctx.measurer, isA<TextMeasurer>());
  });

  test('a renderer measures to the authored size and emits a primitive', () {
    const TextElement el = TextElement(
        id: 'x',
        bounds: JetRect(x: 0, y: 0, width: 30, height: 10),
        text: 'hi');
    expect(const _StubRenderer().measure(el, ctx, const JetConstraints()),
        const JetSize(30, 10));
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    const _StubRenderer()
        .emit(el, ctx, const JetRect(x: 1, y: 2, width: 30, height: 10), out);
    final RectPrimitive prim = out.build().primitives.single as RectPrimitive;
    expect(prim.elementId, 'x');
    expect(prim.bounds, const JetRect(x: 1, y: 2, width: 30, height: 10));
  });
}
