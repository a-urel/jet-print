// BarcodeElementRenderer: a labeled placeholder (real symbology is a later spec).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/barcode_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx =
      RenderContext(measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const BarcodeElementRenderer renderer = BarcodeElementRenderer();
  const JetRect bounds = JetRect(x: 0, y: 0, width: 80, height: 30);

  test('measure returns the authored box size', () {
    const BarcodeElement el = BarcodeElement(
        id: 'b', bounds: bounds, symbology: BarcodeSymbology.code128, data: '123');
    expect(renderer.measure(el, ctx, const JetConstraints()),
        const JetSize(80, 30));
  });

  test('emits a placeholder labeled with the symbology name', () {
    const BarcodeElement el = BarcodeElement(
        id: 'b', bounds: bounds, symbology: BarcodeSymbology.qrCode, data: 'X');
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims[0], isA<RectPrimitive>());
    expect((prims[1] as TextRunPrimitive).lines.single.text, 'qrCode');
    expect(prims[1].elementId, 'b');
  });
}
