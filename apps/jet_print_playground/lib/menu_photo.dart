/// In-code image generation for the restaurant-menu sample.
///
/// Produces uncompressed 24-bit BMP swatches as raw bytes — a vertical gradient
/// between two colors, optionally with a procedurally drawn food glyph on top
/// (see [foodBmp]). BMP is chosen because it is trivial to synthesize
/// byte-by-byte in pure synchronous Dart (no compression, no Flutter binding to
/// *build*) and is accepted by `ui.instantiateImageCodec`, which the engine's
/// painter uses to decode `ImagePrimitive` bytes at paint time. Keeps the sample
/// asset-free and license-clean.
library;

import 'dart:convert';
import 'dart:math';
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

/// A stylised food glyph painted onto a [foodBmp]'s plate. One per dish in the
/// menu sample, so each card reads as the dish rather than an abstract swatch.
enum FoodIcon {
  /// Toasted bread topped with diced tomato and basil.
  bruschetta,

  /// Three fried rings beside a lemon wedge.
  calamari,

  /// A red sauce disc with golden crust, cheese wedges and toppings.
  pizza,

  /// A bowl of nested noodles with an egg yolk and black pepper.
  carbonara,

  /// A salmon-pink fish with a fanned tail.
  salmon,

  /// A layered cocoa-dusted dessert slice.
  tiramisu,

  /// A pistachio scoop on a waffle cone.
  gelato,
}

/// A [gradientBmp] background with a cream "plate" disc and the [icon]'s food
/// glyph drawn on top — a recognisable, asset-free stand-in for a real photo.
///
/// Glyphs are authored against a 64×64 reference and scale linearly to the
/// requested size, so the output stays deterministic (byte-stable) at any
/// dimension — what the round-trip and decode tests rely on.
Uint8List foodBmp({
  required int width,
  required int height,
  required int topRgb,
  required int bottomRgb,
  required FoodIcon icon,
}) {
  final Uint8List bytes = gradientBmp(
    width: width,
    height: height,
    topRgb: topRgb,
    bottomRgb: bottomRgb,
  );
  final _Canvas cv = _Canvas(bytes, width, height);
  _drawPlate(cv);
  _drawGlyph(cv, icon);
  return bytes;
}

/// [foodBmp] base64-encoded — the form carried in a data row's image field.
String foodBmpBase64({
  required int width,
  required int height,
  required int topRgb,
  required int bottomRgb,
  required FoodIcon icon,
}) =>
    base64Encode(foodBmp(
      width: width,
      height: height,
      topRgb: topRgb,
      bottomRgb: bottomRgb,
      icon: icon,
    ));

// ---------------------------------------------------------------------------
// Pixel drawing — a thin, allocation-free layer over the raw BMP byte buffer.
// All coordinates are in top-down image space; the canvas flips Y to the BMP's
// bottom-up storage. No anti-aliasing, so output is fully deterministic.
// ---------------------------------------------------------------------------

/// A mutable view over a 24-bit BMP's pixel bytes in top-down image space.
class _Canvas {
  _Canvas(this.bytes, this.width, this.height)
      : _rowStride = ((width * 3 + 3) ~/ 4) * 4;

  static const int _headerSize = 54;

  final Uint8List bytes;
  final int width;
  final int height;
  final int _rowStride;

  /// Sets the pixel at image-space ([x], [y]) to `0xRRGGBB`, ignoring
  /// out-of-bounds writes so glyph maths never has to clamp.
  void set(int x, int y, int rgb) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    final int fileRow = height - 1 - y; // image top-down -> BMP bottom-up
    final int o = _headerSize + fileRow * _rowStride + x * 3;
    bytes[o] = rgb & 0xFF; // B
    bytes[o + 1] = (rgb >> 8) & 0xFF; // G
    bytes[o + 2] = (rgb >> 16) & 0xFF; // R
  }
}

void _fillRect(_Canvas cv, int x, int y, int w, int h, int rgb) {
  for (int dy = 0; dy < h; dy++) {
    for (int dx = 0; dx < w; dx++) {
      cv.set(x + dx, y + dy, rgb);
    }
  }
}

void _fillDisc(_Canvas cv, int cx, int cy, int r, int rgb) =>
    _fillEllipse(cv, cx, cy, r, r, rgb);

void _fillEllipse(_Canvas cv, int cx, int cy, int rx, int ry, int rgb) {
  if (rx <= 0 || ry <= 0) return;
  for (int dy = -ry; dy <= ry; dy++) {
    for (int dx = -rx; dx <= rx; dx++) {
      final double nx = dx / rx;
      final double ny = dy / ry;
      if (nx * nx + ny * ny <= 1.0) cv.set(cx + dx, cy + dy, rgb);
    }
  }
}

void _strokeRing(_Canvas cv, int cx, int cy, int r, int thickness, int rgb) {
  final int inner = max(0, r - thickness);
  final int outerSq = r * r;
  final int innerSq = inner * inner;
  for (int dy = -r; dy <= r; dy++) {
    for (int dx = -r; dx <= r; dx++) {
      final int d2 = dx * dx + dy * dy;
      if (d2 <= outerSq && d2 >= innerSq) cv.set(cx + dx, cy + dy, rgb);
    }
  }
}

void _fillTriangle(
    _Canvas cv, int ax, int ay, int bx, int by, int cx, int cy, int rgb) {
  final int minX = max(0, min(ax, min(bx, cx)));
  final int maxX = min(cv.width - 1, max(ax, max(bx, cx)));
  final int minY = max(0, min(ay, min(by, cy)));
  final int maxY = min(cv.height - 1, max(ay, max(by, cy)));
  int edge(int px, int py, int x0, int y0, int x1, int y1) =>
      (px - x0) * (y1 - y0) - (py - y0) * (x1 - x0);
  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      final int w0 = edge(x, y, ax, ay, bx, by);
      final int w1 = edge(x, y, bx, by, cx, cy);
      final int w2 = edge(x, y, cx, cy, ax, ay);
      final bool hasNeg = w0 < 0 || w1 < 0 || w2 < 0;
      final bool hasPos = w0 > 0 || w1 > 0 || w2 > 0;
      if (!(hasNeg && hasPos)) cv.set(x, y, rgb);
    }
  }
}

void _line(_Canvas cv, int x0, int y0, int x1, int y1, int rgb, int thickness) {
  // Bresenham, stamping a small block for thickness > 1.
  final int half = thickness ~/ 2;
  int x = x0;
  int y = y0;
  final int dx = (x1 - x0).abs();
  final int dy = -(y1 - y0).abs();
  final int sx = x0 < x1 ? 1 : -1;
  final int sy = y0 < y1 ? 1 : -1;
  int err = dx + dy;
  while (true) {
    _fillRect(cv, x - half, y - half, thickness, thickness, rgb);
    if (x == x1 && y == y1) break;
    final int e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y += sy;
    }
  }
}

// ---------------------------------------------------------------------------
// Glyphs — authored on a 64×64 reference grid, scaled to the live canvas.
// ---------------------------------------------------------------------------

void _drawPlate(_Canvas cv) {
  final int cx = cv.width ~/ 2;
  final int cy = cv.height ~/ 2;
  final int r = (min(cv.width, cv.height) * 0.42).round();
  _fillDisc(cv, cx, cy, r, 0xF4EEE0); // cream plate
  _strokeRing(cv, cx, cy, r, max(1, (r * 0.08).round()), 0xD8CDB4); // rim
}

void _drawGlyph(_Canvas cv, FoodIcon icon) {
  final double ux = cv.width / 64;
  final double uy = cv.height / 64;
  final double ur = (ux + uy) / 2;
  int x(num v) => (v * ux).round();
  int y(num v) => (v * uy).round();
  int w(num v) => max(1, (v * ux).round());
  int h(num v) => max(1, (v * uy).round());
  int r(num v) => max(1, (v * ur).round());

  switch (icon) {
    case FoodIcon.pizza:
      _fillDisc(cv, x(32), y(32), r(17), 0xC8341F); // sauce
      _strokeRing(cv, x(32), y(32), r(17), r(3), 0xE3B362); // crust
      for (final double a in <double>[15, 75, 135, 195, 255, 315]) {
        final double rad = a * pi / 180;
        _line(cv, x(32), y(32), x(32 + 15 * cos(rad)), y(32 + 15 * sin(rad)),
            0xEBCB82, r(1)); // cheese seams
      }
      _fillDisc(cv, x(26), y(27), r(2), 0x3E7D33); // basil
      _fillDisc(cv, x(39), y(35), r(2), 0x7C1B12); // pepperoni
      _fillDisc(cv, x(34), y(23), r(2), 0x8C2418);
      _fillDisc(cv, x(24), y(38), r(2), 0x3E7D33);
    case FoodIcon.salmon:
      _fillTriangle(cv, x(46), y(32), x(60), y(23), x(60), y(41), 0xE8806A);
      _fillEllipse(cv, x(30), y(32), r(17), r(10), 0xE8806A); // body
      _fillEllipse(cv, x(30), y(34), r(15), r(6), 0xF09E89); // belly
      _line(cv, x(25), y(24), x(25), y(40), 0xCF6A55, r(1)); // gill
      _fillDisc(cv, x(20), y(29), r(2), 0x2A2012); // eye
    case FoodIcon.gelato:
      _fillTriangle(cv, x(32), y(56), x(22), y(34), x(42), y(34), 0xC68A3E);
      for (final double k in <double>[26, 31, 36, 41, 46]) {
        _line(cv, x(32), y(56), x(k), y(34), 0xA9712E, r(1)); // waffle hatch
      }
      _fillDisc(cv, x(32), y(28), r(11), 0x8FB14B); // pistachio scoop
      _fillDisc(cv, x(27), y(25), r(5), 0xA9C76A); // highlight
    case FoodIcon.tiramisu:
      _fillRect(cv, x(18), y(22), w(28), h(22), 0xEAD9B0); // sponge
      _fillRect(cv, x(18), y(22), w(28), h(6), 0x5A3A22); // cocoa top
      _fillRect(cv, x(18), y(33), w(28), h(3), 0x9A6A3D); // mid layer
      _fillDisc(cv, x(24), y(25), r(1), 0x36210F); // cocoa dust
      _fillDisc(cv, x(32), y(24), r(1), 0x36210F);
      _fillDisc(cv, x(40), y(26), r(1), 0x36210F);
    case FoodIcon.bruschetta:
      _fillEllipse(cv, x(32), y(38), r(20), r(9), 0xB9863F); // crust
      _fillEllipse(cv, x(32), y(37), r(18), r(7), 0xE7C083); // bread top
      _fillRect(cv, x(24), y(30), w(5), h(5), 0xCB3B28); // tomato dice
      _fillRect(cv, x(31), y(28), w(5), h(5), 0xD4452F);
      _fillRect(cv, x(37), y(31), w(5), h(5), 0xC3331F);
      _fillDisc(cv, x(29), y(27), r(2), 0x4E8F3C); // basil
      _fillDisc(cv, x(36), y(26), r(2), 0x59A046);
    case FoodIcon.calamari:
      _strokeRing(cv, x(25), y(31), r(7), r(3), 0xD9A24E);
      _strokeRing(cv, x(39), y(28), r(8), r(3), 0xCE9743);
      _strokeRing(cv, x(33), y(43), r(7), r(3), 0xE0AE5B);
      _fillTriangle(
          cv, x(48), y(45), x(58), y(40), x(55), y(51), 0xE9D24B); // lemon
    case FoodIcon.carbonara:
      _fillEllipse(cv, x(32), y(40), r(20), r(12), 0xEDE6D6); // bowl
      for (int i = 0; i < 4; i++) {
        _wave(cv, x(15), x(49), y(30 + i * 3), r(2), ux * 9, 0xF0CE78, r(1));
      }
      _fillDisc(cv, x(32), y(33), r(5), 0xE8B23C); // yolk
      _fillDisc(cv, x(24), y(32), r(1), 0x2B2218); // pepper
      _fillDisc(cv, x(41), y(35), r(1), 0x2B2218);
  }
}

/// Draws a horizontal sine wave from [x0] to [x1] at [baseY], used for noodles.
void _wave(_Canvas cv, int x0, int x1, int baseY, int amp, double period,
    int rgb, int thickness) {
  for (int px = x0; px <= x1; px++) {
    final int py = (baseY + amp * sin((px - x0) / period * 2 * pi)).round();
    _fillRect(cv, px, py, thickness, thickness, rgb);
  }
}
