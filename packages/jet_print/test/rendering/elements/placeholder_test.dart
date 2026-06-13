// emitPlaceholder: an outline rect + a measured label, for render-don't-crash.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/placeholder.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx = RenderContext(
      measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));

  test('emits an outline rect then a label text run, both tagged', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    emitPlaceholder(
        out, const JetRect(x: 2, y: 3, width: 40, height: 20), 'image', ctx,
        elementId: 'img1');
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims.length, 2);

    final RectPrimitive rect = prims[0] as RectPrimitive;
    expect(rect.bounds, const JetRect(x: 2, y: 3, width: 40, height: 20));
    expect(rect.stroke, isNotNull);
    expect(rect.fill, isNull);
    expect(rect.elementId, 'img1');

    final TextRunPrimitive label = prims[1] as TextRunPrimitive;
    expect(label.lines.single.text, 'image');
    expect(label.fontFamily, 'Default');
    expect(label.elementId, 'img1');
  });
}
