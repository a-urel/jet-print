import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/image_element_codec.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('image', const ImageElementCodec());

void main() {
  group('ImageElement', () {
    test('is a ReportElement with the "image" type key and default fit', () {
      const ImageElement e = ImageElement(
        id: 'logo',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        source: UrlImageSource('https://example.com/logo.png'),
      );
      expect(e, isA<ReportElement>());
      expect(e.typeKey, 'image');
      expect(e.fit, JetBoxFit.contain);
    });

    test('round-trips with a url source and explicit fit', () {
      final ElementCodecRegistry registry = _registry();
      const ImageElement e = ImageElement(
        id: 'logo',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        source: UrlImageSource('https://example.com/logo.png'),
        fit: JetBoxFit.cover,
      );
      expect(registry.decode(registry.encode(e)), e);
    });

    test('round-trips with a field source', () {
      final ElementCodecRegistry registry = _registry();
      const ImageElement e = ImageElement(
        id: 'photo',
        bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
        source: FieldImageSource('product_image'),
      );
      expect(registry.decode(registry.encode(e)), e);
    });
  });
}
