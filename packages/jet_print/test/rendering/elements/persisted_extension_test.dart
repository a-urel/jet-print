// FLAGSHIP: a custom element type round-trips through report_codec AND renders,
// with zero edits to library src/ (Constitution II — persistence + rendering).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_renderer.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

/// A custom element type defined ENTIRELY in test code.
class StarElement extends ReportElement {
  const StarElement(
      {required super.id, required super.bounds, required this.points});
  final int points;
  @override
  String get typeKey => 'star';
  @override
  StarElement withBounds(JetRect bounds) =>
      StarElement(id: id, bounds: bounds, points: points);
  @override
  bool operator ==(Object other) =>
      other is StarElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.points == points;
  @override
  int get hashCode => Object.hash(id, bounds, points);
}

class StarCodec extends ElementCodec<StarElement> {
  const StarCodec();
  @override
  StarElement fromJson(Map<String, Object?> json) => StarElement(
        id: json['id']! as String,
        bounds:
            JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        points: (json['points']! as num).toInt(),
      );
  @override
  Map<String, Object?> toJson(StarElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'points': element.points,
      };
}

class StarRenderer extends ElementRenderer<StarElement> {
  const StarRenderer();
  @override
  JetSize measure(StarElement el, RenderContext ctx, JetConstraints c) =>
      JetSize(el.bounds.width, el.bounds.height);
  @override
  void emit(StarElement el, RenderContext ctx, JetRect bounds,
          FrameBuilder out) =>
      out.add(RectPrimitive(
          bounds: bounds, stroke: JetColor.black, elementId: el.id));
}

void main() {
  test(
      'custom type round-trips through report_codec AND renders, zero core edits',
      () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    reg.register<StarElement>('star', const StarCodec(), const StarRenderer());

    const StarElement star = StarElement(
        id: 's1',
        bounds: JetRect(x: 10, y: 20, width: 30, height: 30),
        points: 5);
    final ReportTemplate template = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
            type: BandType.detail, height: 50, elements: <ReportElement>[star]),
      ],
    );

    // (a) Persist through the REAL codec path: encode -> decode -> re-encode.
    final Map<String, Object?> json = encodeTemplate(template, reg.codecs);
    final ReportTemplate decoded = decodeTemplate(json, reg.codecs);
    expect(encodeTemplate(decoded, reg.codecs), json); // deep map equality
    expect(decoded.bands.single.elements.single, star); // typed, value-equal

    // (b) Render through the registered renderer.
    final FrameBuilder out = FrameBuilder(template.page);
    reg.renderers.rendererFor(star).emit(
          star,
          RenderContext(
              measurer: MetricsTextMeasurer(FontRegistry()..registerDefault())),
          star.bounds,
          out,
        );
    final FramePrimitive prim = out.build().primitives.single;
    expect(prim, isA<RectPrimitive>());
    expect((prim as RectPrimitive).elementId, 's1');
  });
}
