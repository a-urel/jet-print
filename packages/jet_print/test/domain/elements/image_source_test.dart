import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';

void main() {
  group('JetImageSource', () {
    test('UrlImageSource round-trips', () {
      const JetImageSource s = UrlImageSource('https://example.com/logo.png');
      expect(s.toJson(), <String, Object?>{
        'kind': 'url',
        'url': 'https://example.com/logo.png',
      });
      expect(JetImageSource.fromJson(s.toJson()), s);
    });

    test('FieldImageSource round-trips', () {
      const JetImageSource s = FieldImageSource('product_image');
      expect(JetImageSource.fromJson(s.toJson()), s);
    });

    test('BytesImageSource round-trips through base64', () {
      final JetImageSource s =
          BytesImageSource(Uint8List.fromList(<int>[1, 2, 3, 250]));
      final JetImageSource back = JetImageSource.fromJson(s.toJson());
      expect(back, isA<BytesImageSource>());
      expect((back as BytesImageSource).bytes, <int>[1, 2, 3, 250]);
    });

    test('throws on an unknown source kind', () {
      expect(
        () => JetImageSource.fromJson(<String, Object?>{'kind': 'satellite'}),
        throwsFormatException,
      );
    });
  });
}
