import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/barcode_element_codec.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/unknown_element.dart';

ElementCodecRegistry _registryWithText() =>
    ElementCodecRegistry()..register('text', const TextElementCodec());

TextElement _styledText(JetTextStyle style) => TextElement(
      id: 't1',
      bounds: const JetRect(x: 1, y: 2, width: 3, height: 4),
      text: 'hi',
      style: style,
    );

void main() {
  group('ElementCodecRegistry', () {
    test('encodes an element with its type key embedded', () {
      final ElementCodecRegistry registry = _registryWithText();
      const TextElement element = TextElement(
        id: 't1',
        bounds: JetRect(x: 1, y: 2, width: 3, height: 4),
        text: 'hi',
      );
      expect(registry.encode(element), <String, Object?>{
        'type': 'text',
        'id': 't1',
        'bounds': <String, Object?>{'x': 1.0, 'y': 2.0, 'w': 3.0, 'h': 4.0},
        'text': 'hi',
      });
    });

    test('round-trips a registered element', () {
      final ElementCodecRegistry registry = _registryWithText();
      const TextElement element = TextElement(
        id: 't1',
        bounds: JetRect(x: 1, y: 2, width: 3, height: 4),
        text: 'hi',
      );
      final ReportElement decoded = registry.decode(registry.encode(element));
      expect(decoded, element);
    });

    test('decodes an unregistered type to a lossless UnknownElement', () {
      final ElementCodecRegistry registry = _registryWithText();
      final Map<String, Object?> json = <String, Object?>{
        'type': 'sparkline',
        'id': 's1',
        'bounds': <String, Object?>{'x': 0, 'y': 0, 'w': 10, 'h': 5},
        'series': <Object?>[3, 1, 4],
      };
      final ReportElement decoded = registry.decode(json);
      expect(decoded, isA<UnknownElement>());
      // Byte-for-byte round-trip: re-encoding yields the original JSON.
      expect(registry.encode(decoded), equals(json));
    });

    test('throws when element JSON has no string "type"', () {
      final ElementCodecRegistry registry = _registryWithText();
      expect(
        () => registry.decode(<String, Object?>{'id': 'x'}),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('throws StateError encoding an unregistered element type', () {
      final ElementCodecRegistry registry = ElementCodecRegistry();
      const TextElement element = TextElement(
        id: 'x',
        bounds: JetRect.zero,
        text: '',
      );
      expect(() => registry.encode(element), throwsStateError);
    });

    test('wraps a malformed element field in ReportFormatException', () {
      final ElementCodecRegistry registry = _registryWithText();
      final Map<String, Object?> json = <String, Object?>{
        'type': 'text',
        'id': 't',
        'bounds': <String, Object?>{'x': 0, 'y': 0, 'w': 1, 'h': 1},
        'text': 'x',
        'style': <String, Object?>{
          'fontSize': 12,
          'weight': 'huge', // not a JetFontWeight name
          'italic': false,
          'color': '#FF000000',
          'align': 'left',
        },
      };
      expect(
          () => registry.decode(json), throwsA(isA<ReportFormatException>()));
    });

    test('preserves unknown JSON even if the source map is later mutated', () {
      final ElementCodecRegistry registry = _registryWithText();
      final List<Object?> series = <Object?>[3, 1, 4];
      final Map<String, Object?> json = <String, Object?>{
        'type': 'sparkline',
        'id': 's1',
        'bounds': <String, Object?>{'x': 0, 'y': 0, 'w': 10, 'h': 5},
        'series': series,
      };
      final ReportElement decoded = registry.decode(json);
      // Mutate the original nested structures after decoding.
      series.add(99);
      (json['bounds']! as Map)['x'] = 999;
      // The decoded element must still re-encode to the ORIGINAL shape.
      expect(registry.encode(decoded), <String, Object?>{
        'type': 'sparkline',
        'id': 's1',
        'bounds': <String, Object?>{'x': 0, 'y': 0, 'w': 10, 'h': 5},
        'series': <Object?>[3, 1, 4],
      });
    });
  });

  // --- 021 format properties: underline + unknown family wire rules ---------
  group('TextElementCodec — underline (021 / C3, C10)', () {
    test('underline: true serializes and round-trips', () {
      final ElementCodecRegistry registry = _registryWithText();
      final TextElement element =
          _styledText(const JetTextStyle(underline: true));
      final Map<String, Object?> json = registry.encode(element);
      expect((json['style']! as Map)['underline'], isTrue);
      expect(registry.decode(json), element);
    });

    test('underline: false is omitted from the wire', () {
      final ElementCodecRegistry registry = _registryWithText();
      final Map<String, Object?> json =
          registry.encode(_styledText(const JetTextStyle(fontSize: 20)));
      expect((json['style']! as Map).containsKey('underline'), isFalse);
    });

    test('a pre-021 style map (no underline key) loads as not underlined', () {
      final ElementCodecRegistry registry = _registryWithText();
      final Map<String, Object?> pre021 = <String, Object?>{
        'type': 'text',
        'id': 't1',
        'bounds': <String, Object?>{'x': 1, 'y': 2, 'w': 3, 'h': 4},
        'text': 'hi',
        'style': <String, Object?>{
          'fontSize': 20.0,
          'weight': 'normal',
          'italic': false,
          'color': '#FF000000',
          'align': 'left',
        },
      };
      final TextElement decoded = registry.decode(pre021) as TextElement;
      expect(decoded.style.underline, isFalse);
    });

    test('fallback-plus-underline is no longer omitted as a fallback style',
        () {
      final ElementCodecRegistry registry = _registryWithText();
      // A style equal to fallback in every pre-021 field, but underlined: it
      // is NOT equal to fallback any more, so it must serialize.
      final Map<String, Object?> json =
          registry.encode(_styledText(const JetTextStyle(underline: true)));
      expect(json.containsKey('style'), isTrue,
          reason: 'underline distinguishes the style from the fallback');
      // And a true fallback style is still omitted (compact wire unchanged).
      expect(
          registry
              .encode(_styledText(JetTextStyle.fallback))
              .containsKey('style'),
          isFalse);
    });

    test('an unknown fontFamily string survives load→save untouched', () {
      final ElementCodecRegistry registry = _registryWithText();
      final Map<String, Object?> json = registry.encode(_styledText(
          const JetTextStyle(fontFamily: 'SomeUnregisteredFamily')));
      final ReportElement decoded = registry.decode(json);
      expect(
          (decoded as TextElement).style.fontFamily, 'SomeUnregisteredFamily');
      expect(registry.encode(decoded), equals(json),
          reason: 'the stored family is preserved byte-for-byte');
    });
  });

  // --- 021 format properties: barcode color wire rules (US3 / C8, C10) ------
  group('BarcodeElementCodec — color (021 / US3)', () {
    const BarcodeElementCodec codec = BarcodeElementCodec();
    const JetRect bounds = JetRect(x: 1, y: 2, width: 40, height: 40);

    BarcodeElement barcode(JetColor color) => BarcodeElement(
          id: 'b',
          bounds: bounds,
          symbology: BarcodeSymbology.qrCode,
          data: '42',
          color: color,
        );

    test('color is omitted when black (the compact default)', () {
      final Map<String, Object?> json = codec.toJson(barcode(JetColor.black));
      expect(json.containsKey('color'), isFalse);
      expect(codec.fromJson(json).color, JetColor.black);
    });

    test('a non-black color round-trips', () {
      final BarcodeElement el = barcode(const JetColor(0xFF1E40AF));
      final Map<String, Object?> json = codec.toJson(el);
      expect(json['color'], '#FF1E40AF');
      expect(codec.fromJson(json), el);
    });

    test('a translucent color round-trips with alpha intact', () {
      final BarcodeElement el = barcode(const JetColor(0x801E40AF));
      final Map<String, Object?> json = codec.toJson(el);
      expect(json['color'], '#801E40AF');
      expect(codec.fromJson(json).color, const JetColor(0x801E40AF));
    });
  });
}
