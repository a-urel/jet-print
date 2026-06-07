import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('text', const TextElementCodec());

void main() {
  group('TextElement style', () {
    test('defaults to the fallback style', () {
      const TextElement e = TextElement(
        id: 't',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        text: 'x',
      );
      expect(e.style, JetTextStyle.fallback);
    });

    test('default-style text omits the "style" key (Part 1 wire shape)', () {
      final ElementCodecRegistry registry = _registry();
      const TextElement e = TextElement(
        id: 't',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        text: 'x',
      );
      expect(registry.encode(e).containsKey('style'), isFalse);
    });

    test('styled text round-trips its style', () {
      final ElementCodecRegistry registry = _registry();
      const TextElement e = TextElement(
        id: 'title',
        bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
        text: 'INVOICE',
        style: JetTextStyle(
          fontSize: 20,
          weight: JetFontWeight.bold,
          color: JetColor(0xFF1A73E8),
          align: JetTextAlign.center,
        ),
      );
      expect(registry.encode(e).containsKey('style'), isTrue);
      expect(registry.decode(registry.encode(e)), e);
    });
  });
}
