/// In-code image generation for the restaurant-menu sample.
///
/// Produces uncompressed 24-bit BMP swatches as raw bytes — a vertical gradient
/// between two colors. BMP is chosen because it is trivial to synthesize
/// byte-by-byte in pure synchronous Dart (no compression, no Flutter binding to
/// *build*) and is accepted by `ui.instantiateImageCodec`, which the engine's
/// painter uses to decode `ImagePrimitive` bytes at paint time. Keeps the sample
/// asset-free and license-clean.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Builds a 24-bit BMP of [width]×[height] with a vertical gradient from
/// [topRgb] (top row) to [bottomRgb] (bottom row). Colors are `0xRRGGBB`.
Uint8List gradientBmp({
  required int width,
  required int height,
  required int topRgb,
  required int bottomRgb,
}) {
  const int headerSize = 54; // 14-byte file header + 40-byte info header.
  // Each pixel is 3 bytes (BGR); rows are padded to a 4-byte boundary.
  final int rowStride = ((width * 3 + 3) ~/ 4) * 4;
  final int pixelBytes = rowStride * height;
  final int fileSize = headerSize + pixelBytes;

  final Uint8List bytes = Uint8List(fileSize);
  final ByteData bd = ByteData.sublistView(bytes);

  // BITMAPFILEHEADER.
  bytes[0] = 0x42; // 'B'
  bytes[1] = 0x4D; // 'M'
  bd.setUint32(2, fileSize, Endian.little);
  bd.setUint32(10, headerSize, Endian.little); // pixel-data offset

  // BITMAPINFOHEADER.
  bd.setUint32(14, 40, Endian.little); // this header's size
  bd.setInt32(18, width, Endian.little);
  bd.setInt32(22, height, Endian.little); // positive => bottom-up rows
  bd.setUint16(26, 1, Endian.little); // color planes
  bd.setUint16(28, 24, Endian.little); // bits per pixel
  bd.setUint32(30, 0, Endian.little); // BI_RGB (no compression)
  bd.setUint32(34, pixelBytes, Endian.little); // raw image size

  final int tr = (topRgb >> 16) & 0xFF;
  final int tg = (topRgb >> 8) & 0xFF;
  final int tb = topRgb & 0xFF;
  final int br = (bottomRgb >> 16) & 0xFF;
  final int bg = (bottomRgb >> 8) & 0xFF;
  final int bb = bottomRgb & 0xFF;

  for (int y = 0; y < height; y++) {
    // BMP rows are stored bottom-up: file row 0 is the image's bottom row.
    final int imageRow = height - 1 - y;
    final double t = height == 1 ? 0 : imageRow / (height - 1);
    final int r = (tr + (br - tr) * t).round();
    final int g = (tg + (bg - tg) * t).round();
    final int b = (tb + (bb - tb) * t).round();
    int o = headerSize + y * rowStride;
    for (int x = 0; x < width; x++) {
      bytes[o++] = b; // BMP pixels are stored BGR.
      bytes[o++] = g;
      bytes[o++] = r;
    }
    // Trailing row-padding bytes are already zero.
  }
  return bytes;
}

/// [gradientBmp] base64-encoded — the form carried in a data row's image field.
String gradientBmpBase64({
  required int width,
  required int height,
  required int topRgb,
  required int bottomRgb,
}) =>
    base64Encode(gradientBmp(
      width: width,
      height: height,
      topRgb: topRgb,
      bottomRgb: bottomRgb,
    ));
