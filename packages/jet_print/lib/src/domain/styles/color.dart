/// A pure-Dart color value (no `dart:ui`).
library;

/// An immutable ARGB32 color. Serialized as a human-inspectable hex string
/// `#AARRGGBB` (Constitution V); in memory it is a packed [argb] int.
class JetColor {
  /// Creates a color from a packed 0xAARRGGBB value.
  const JetColor(this.argb);

  /// Creates a color from 0–255 alpha/red/green/blue channels.
  const JetColor.fromARGB(int a, int r, int g, int b)
      : argb = (a << 24) | (r << 16) | (g << 8) | b;

  /// Parses `#AARRGGBB` or `#RRGGBB` (the latter assumes opaque alpha).
  factory JetColor.fromJson(String hex) {
    var h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length == 6) {
      h = 'FF$h';
    }
    if (h.length != 8) {
      throw FormatException('Invalid color hex "$hex".');
    }
    return JetColor(int.parse(h, radix: 16));
  }

  /// Opaque black.
  static const JetColor black = JetColor(0xFF000000);

  /// The packed 0xAARRGGBB value.
  final int argb;

  /// Serializes to an uppercase `#AARRGGBB` hex string.
  String toJson() => '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) => other is JetColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() => 'JetColor(${toJson()})';
}
