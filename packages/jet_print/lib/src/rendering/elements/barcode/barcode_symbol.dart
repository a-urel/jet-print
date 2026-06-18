/// First-party, package-agnostic barcode geometry (spec 036). The encoder seam
/// returns these; the renderer translates them into frame primitives. Pure Dart.
library;

/// Horizontal alignment of an HRI text run.
enum BarcodeHriAlign { left, center, right }

/// A single filled bar (1D) or module (2D) rectangle, in the symbol's own
/// coordinate space `[0..spaceWidth] x [0..spaceHeight]`.
class BarcodeModule {
  /// Creates a module rect.
  const BarcodeModule(this.left, this.top, this.width, this.height);

  /// Left/top/width/height, in symbol-space units.
  final double left, top, width, height;

  @override
  bool operator ==(Object other) =>
      other is BarcodeModule &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'BarcodeModule($left, $top, $width, $height)';
}

/// A human-readable text run beneath a 1D symbol, in symbol-space units.
class BarcodeHriText {
  /// Creates an HRI text run.
  const BarcodeHriText({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.text,
    required this.align,
  });

  /// Bounds in symbol-space units.
  final double left, top, width, height;

  /// The displayed text.
  final String text;

  /// Horizontal alignment within [left]..[left]+[width].
  final BarcodeHriAlign align;

  @override
  bool operator ==(Object other) =>
      other is BarcodeHriText &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height &&
      other.text == text &&
      other.align == align;

  @override
  int get hashCode => Object.hash(left, top, width, height, text, align);

  @override
  String toString() => 'BarcodeHriText("$text" @ $left,$top)';
}

/// The positioned geometry of an encoded symbol, in a coordinate space of
/// [spaceWidth] x [spaceHeight]. [isTwoD] symbols have square modules.
class BarcodeSymbol {
  /// Creates a symbol geometry.
  const BarcodeSymbol({
    required this.modules,
    required this.texts,
    required this.spaceWidth,
    required this.spaceHeight,
    required this.isTwoD,
  });

  /// Filled bar/module rectangles.
  final List<BarcodeModule> modules;

  /// HRI text runs (empty for 2D or when text is disabled).
  final List<BarcodeHriText> texts;

  /// The coordinate-space extents the geometry was laid out in.
  final double spaceWidth, spaceHeight;

  /// Whether this is a 2D matrix symbology.
  final bool isTwoD;
}
