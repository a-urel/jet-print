// Confirms the in-code BMP generator emits real, decodable image bytes — the
// thing the engine's painter (ui.instantiateImageCodec) needs at paint time.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print_playground/menu_photo.dart';

void main() {
  group('gradientBmp', () {
    test('has a well-formed BMP header and exact size', () {
      final Uint8List b =
          gradientBmp(width: 8, height: 6, topRgb: 0xFF0000, bottomRgb: 0x0000FF);
      // 'BM' magic.
      expect(b[0], 0x42);
      expect(b[1], 0x4D);
      final ByteData bd = ByteData.sublistView(b);
      // Pixel-data offset is right after the 14+40 byte headers.
      expect(bd.getUint32(10, Endian.little), 54);
      // 24bpp, BI_RGB, declared width/height.
      expect(bd.getInt32(18, Endian.little), 8);
      expect(bd.getInt32(22, Endian.little), 6);
      expect(bd.getUint16(28, Endian.little), 24);
      expect(bd.getUint32(30, Endian.little), 0);
      // Row stride for width 8 = 24 bytes (already 4-aligned); 6 rows + 54 header.
      expect(b.length, 54 + 24 * 6);
    });

    testWidgets('decodes through the Flutter codec to the requested size',
        (WidgetTester tester) async {
      final Uint8List b =
          gradientBmp(width: 12, height: 9, topRgb: 0xE8B04B, bottomRgb: 0x7A3B12);
      final ui.Codec codec = await ui.instantiateImageCodec(b);
      final ui.FrameInfo frame = await codec.getNextFrame();
      expect(frame.image.width, 12);
      expect(frame.image.height, 9);
    });

    test('base64 variant round-trips to the same bytes', () {
      final Uint8List raw =
          gradientBmp(width: 4, height: 4, topRgb: 0x112233, bottomRgb: 0x445566);
      final String b64 = gradientBmpBase64(
          width: 4, height: 4, topRgb: 0x112233, bottomRgb: 0x445566);
      expect(base64Decode(b64), raw);
    });
  });
}
