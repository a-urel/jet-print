import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';
import 'package:jet_print/src/domain/unknown_element.dart';

ElementCodecRegistry _registryWithText() =>
    ElementCodecRegistry()..register('text', const TextElementCodec());

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
}
