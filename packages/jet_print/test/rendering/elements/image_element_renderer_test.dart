// ImageElementRenderer: BytesImageSource -> ImagePrimitive; url/field -> placeholder.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/image_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx = RenderContext(
      measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const ImageElementRenderer renderer = ImageElementRenderer();
  const JetRect bounds = JetRect(x: 0, y: 0, width: 50, height: 40);

  test('measure returns the authored box size', () {
    final ImageElement el = ImageElement(
        id: 'i', bounds: bounds, source: BytesImageSource(Uint8List(0)));
    expect(renderer.measure(el, ctx, const JetConstraints()),
        const JetSize(50, 40));
  });

  test('embedded bytes emit an ImagePrimitive with the element fit', () {
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final ImageElement el = ImageElement(
        id: 'i',
        bounds: bounds,
        source: BytesImageSource(bytes),
        fit: JetBoxFit.cover);
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final ImagePrimitive p = out.build().primitives.single as ImagePrimitive;
    expect(p.bytes, bytes);
    expect(p.fit, JetBoxFit.cover);
    expect(p.bounds, bounds);
    expect(p.elementId, 'i');
  });

  test('a url source (unresolved in 007a) emits a placeholder', () {
    const ImageElement el = ImageElement(
        id: 'i', bounds: bounds, source: UrlImageSource('https://x/y.png'));
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims[0], isA<RectPrimitive>());
    expect((prims[1] as TextRunPrimitive).lines.single.text, 'image');
  });

  test('a field source (unresolved in 007a) also emits a placeholder', () {
    // FieldImageSource is a distinct source kind; the placeholder branch must
    // cover it too, not just UrlImageSource.
    const ImageElement el = ImageElement(
        id: 'i', bounds: bounds, source: FieldImageSource('photo'));
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims[0], isA<RectPrimitive>());
    expect((prims[1] as TextRunPrimitive).lines.single.text, 'image');
  });
}
