// TextElementRenderer: measure/emit + the section 7.1 local wrap-width invariant.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/text_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

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
    renderer.emit(el, ctx, const JetRect(x: 5, y: 5, width: 40, height: 100), out);
    final TextRunPrimitive run =
        out.build().primitives.single as TextRunPrimitive;
    expect(run.fontFamily, 'JetSans');
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
    renderer.emit(el, ctx, const JetRect(x: 5, y: 5, width: 9999, height: 100), out);
    final TextRunPrimitive run =
        out.build().primitives.single as TextRunPrimitive;
    expect(run.lines.map((l) => l.text).toList(), authored);
    expect(run.lines.length, greaterThan(1)); // sanity: the text actually wrapped at 40
  });
}
