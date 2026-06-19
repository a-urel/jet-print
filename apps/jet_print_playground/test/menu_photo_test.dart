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
      // Image decoding is real async I/O — it must run in the real async zone
      // (runAsync), not the widget tester's fake-async clock, or the codec
      // future never completes and the test hangs.
      final ui.Image image = (await tester.runAsync(() async {
        final ui.Codec codec = await ui.instantiateImageCodec(b);
        return (await codec.getNextFrame()).image;
      }))!;
      addTearDown(image.dispose);
      expect(image.width, 12);
      expect(image.height, 9);
    });

    test('base64 variant round-trips to the same bytes', () {
      final Uint8List raw =
          gradientBmp(width: 4, height: 4, topRgb: 0x112233, bottomRgb: 0x445566);
      final String b64 = gradientBmpBase64(
          width: 4, height: 4, topRgb: 0x112233, bottomRgb: 0x445566);
      expect(base64Decode(b64), raw);
    });
  });

  group('foodBmp', () {
    test('every FoodIcon paints a glyph over the plain gradient', () {
      // Same dimensions/colors as the gradient background; a food BMP must
      // differ from it because the plate + glyph are drawn on top.
      final Uint8List plain =
          gradientBmp(width: 64, height: 64, topRgb: 0xE8C07A, bottomRgb: 0xB6772E);
      for (final FoodIcon icon in FoodIcon.values) {
        final Uint8List withIcon = foodBmp(
          width: 64,
          height: 64,
          topRgb: 0xE8C07A,
          bottomRgb: 0xB6772E,
          icon: icon,
        );
        expect(withIcon.length, plain.length,
            reason: 'same dimensions => same byte length for $icon');
        expect(withIcon, isNot(equals(plain)),
            reason: '$icon should paint a plate + glyph over the gradient');
      }
    });

    test('distinct icons produce distinct images', () {
      final Uint8List pizza = foodBmp(
          width: 64, height: 64, topRgb: 0xE7553B, bottomRgb: 0x7E1F12, icon: FoodIcon.pizza);
      final Uint8List salmon = foodBmp(
          width: 64, height: 64, topRgb: 0xE7553B, bottomRgb: 0x7E1F12, icon: FoodIcon.salmon);
      expect(pizza, isNot(equals(salmon)));
    });

    testWidgets('decodes through the Flutter codec to the requested size',
        (WidgetTester tester) async {
      final Uint8List b = foodBmp(
          width: 64, height: 64, topRgb: 0xE8C07A, bottomRgb: 0xB6772E, icon: FoodIcon.gelato);
      final ui.Image image = (await tester.runAsync(() async {
        final ui.Codec codec = await ui.instantiateImageCodec(b);
        return (await codec.getNextFrame()).image;
      }))!;
      addTearDown(image.dispose);
      expect(image.width, 64);
      expect(image.height, 64);
    });

    test('base64 variant round-trips to the same bytes', () {
      final Uint8List raw = foodBmp(
          width: 32, height: 32, topRgb: 0x112233, bottomRgb: 0x445566, icon: FoodIcon.pizza);
      final String b64 = foodBmpBase64(
          width: 32, height: 32, topRgb: 0x112233, bottomRgb: 0x445566, icon: FoodIcon.pizza);
      expect(base64Decode(b64), raw);
    });
  });
}
