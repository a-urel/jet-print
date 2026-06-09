// UnknownElementRenderer: a placeholder labeled with the unrecognized typeKey.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/unknown_element.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/unknown_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx = RenderContext(
      measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const UnknownElementRenderer renderer = UnknownElementRenderer();

  UnknownElement makeUnknown() => UnknownElement(
        typeKey: 'gizmo',
        rawJson: <String, Object?>{
          'type': 'gizmo',
          'id': 'g1',
          'bounds': <String, Object?>{'x': 0, 'y': 0, 'w': 80, 'h': 15},
        },
      );

  test('measure returns the best-effort bounds from the preserved JSON', () {
    expect(renderer.measure(makeUnknown(), ctx, const JetConstraints()),
        const JetSize(80, 15));
  });

  test('emits a placeholder labeled with the unknown typeKey', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    final UnknownElement el = makeUnknown();
    renderer.emit(el, ctx, el.bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims[0], isA<RectPrimitive>());
    expect((prims[1] as TextRunPrimitive).lines.single.text, 'Unknown: gizmo');
    expect(prims[1].elementId, 'g1');
  });
}
