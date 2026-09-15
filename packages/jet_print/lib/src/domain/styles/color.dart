/// A pure-Dart color value (no `dart:ui`).
library;

import '../value_equality.dart';

/// An immutable ARGB32 color. Serialized as a human-inspectable hex string
/// `#AARRGGBB`; in memory it is a packed [argb] int.
class JetColor with ValueEquality {
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
  List<Object?> get props => <Object?>[argb];

  @override
  String toString() => 'JetColor(${toJson()})';
}
