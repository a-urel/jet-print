// TextElementRenderer: measure/emit + the section 7.1 local wrap-width invariant.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/text_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  final MetricsTextMeasurer measurer =
      MetricsTextMeasurer(FontRegistry()..registerDefault());
  final RenderContext ctx = RenderContext(measurer: measurer);
  const TextElementRenderer renderer = TextElementRenderer();

  const TextElement el = TextElement(
    id: 't',
    bounds: JetRect(x: 0, y: 0, width: 40, height: 100),
    text: 'the quick brown fox',
  );

  test('emit produces one TextRunPrimitive carrying the resolved family', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(
        el, ctx, const JetRect(x: 5, y: 5, width: 40, height: 100), out);
    final TextRunPrimitive run =
        out.build().primitives.single as TextRunPrimitive;
    expect(run.fontFamily, 'Default');
    expect(run.style, el.style);
    expect(run.elementId, 't');
    expect(run.bounds, const JetRect(x: 5, y: 5, width: 40, height: 100));
  });

  test('measure wraps at the authored width, ignoring the constraint', () {
    final JetSize size =
        renderer.measure(el, ctx, const JetConstraints(maxWidth: 9999));
    final JetSize expected =
        measurer.measure(el.text, el.style, maxWidth: 40).size;
    expect(size, expected);
  });

  test('emit wraps at the authored width, not the passed bounds width', () {
    final List<String> authored = measurer
        .measure(el.text, el.style, maxWidth: 40)
        .lines
        .map((l) => l.text)
        .toList();
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    // Deliberately WIDER emit bounds: wrapping must still use the authored 40.
    renderer.emit(
        el, ctx, const JetRect(x: 5, y: 5, width: 9999, height: 100), out);
    final TextRunPrimitive run =
        out.build().primitives.single as TextRunPrimitive;
    expect(run.lines.map((l) => l.text).toList(), authored);
    expect(run.lines.length,
        greaterThan(1)); // sanity: the text actually wrapped at 40
  });

  test('measure and emit pin identical line geometry (section 7.1 invariant)',
      () {
    // Directly cross-check the two renderer paths against ONE measurement, so a
    // regression that diverged measure-sizing from emit-wrapping would be caught.
    final MeasuredText measured =
        measurer.measure(el.text, el.style, maxWidth: el.bounds.width);
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(
        el, ctx, const JetRect(x: 0, y: 0, width: 40, height: 100), out);
    final TextRunPrimitive run =
        out.build().primitives.single as TextRunPrimitive;
    // emit's lines == the lines measure is based on (identical geometry).
    expect(run.lines, measured.lines);
    // measure() reports that same block size.
    expect(renderer.measure(el, ctx, const JetConstraints()), measured.size);
  });

  test('emit carries a registered custom font family end-to-end', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    reg.register('Custom', reg.bytesFor(null)); // custom family, default bytes
    final RenderContext customCtx =
        RenderContext(measurer: MetricsTextMeasurer(reg));
    const TextElement styled = TextElement(
      id: 't2',
      bounds: JetRect(x: 0, y: 0, width: 200, height: 20),
      text: 'hi',
      style: JetTextStyle(fontFamily: 'Custom'),
    );
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(styled, customCtx, styled.bounds, out);
    expect((out.build().primitives.single as TextRunPrimitive).fontFamily,
        'Custom');
  });
}
