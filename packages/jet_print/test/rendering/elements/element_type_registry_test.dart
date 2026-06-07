// ElementTypeRegistry: pairs codec + renderer; composes the codec registry;
// registerBuiltInElementTypes wires text/shape/image/barcode; last-write-wins.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';
import 'package:jet_print/src/rendering/elements/renderers/barcode_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/image_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/shape_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/text_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/unknown_element_renderer.dart';

void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 1, height: 1);

  test('built-ins register both a codec and a renderer per type', () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);

    const TextElement text = TextElement(id: 't', bounds: r, text: 'x');
    expect(reg.renderers.rendererFor(text), isA<TextElementRenderer>());

    // The codec half drives serialization: encode produces a typed map.
    expect(reg.codecs.encode(text)['type'], 'text');
  });

  test('renderers for all built-in types are wired (direct instances)', () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    expect(
        reg.renderers.rendererFor(
            const ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle)),
        isA<ShapeElementRenderer>());
    expect(
        reg.renderers.rendererFor(
            ImageElement(id: 'i', bounds: r, source: BytesImageSource(Uint8List(0)))),
        isA<ImageElementRenderer>());
    expect(
        reg.renderers.rendererFor(const BarcodeElement(
            id: 'b', bounds: r, symbology: BarcodeSymbology.code128, data: '1')),
        isA<BarcodeElementRenderer>());
  });

  test('register is last-write-wins (built-in override)', () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    // Override 'text' with a different renderer. Widening E to ReportElement is
    // the documented covariance path (UnknownElementRenderer is
    // ElementRenderer<ReportElement>, not <TextElement>).
    reg.register<ReportElement>(
        'text', const TextElementCodec(), const UnknownElementRenderer());
    const TextElement text = TextElement(id: 't', bounds: r, text: 'x');
    expect(reg.renderers.rendererFor(text), isA<UnknownElementRenderer>());
  });

  test('wires all four codecs (round-trip via reg.codecs, not just text)', () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    final List<ReportElement> elements = <ReportElement>[
      const TextElement(id: 't', bounds: r, text: 'x'),
      const ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle),
      ImageElement(
          id: 'i', bounds: r, source: BytesImageSource(Uint8List.fromList(<int>[1, 2]))),
      const BarcodeElement(
          id: 'b', bounds: r, symbology: BarcodeSymbology.code128, data: '1'),
    ];
    for (final ReportElement el in elements) {
      final Map<String, Object?> encoded = reg.codecs.encode(el);
      final ReportElement decoded = reg.codecs.decode(encoded);
      expect(decoded.typeKey, el.typeKey,
          reason: 'codec for "${el.typeKey}" not wired by registerBuiltInElementTypes');
      expect(decoded.runtimeType, el.runtimeType); // a real type, not UnknownElement
    }
  });
}
