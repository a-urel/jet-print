/// Pure-Dart geometry value types for the report model.
///
/// These deliberately mirror the *shape* of `dart:ui`'s geometry types but carry
/// **no Flutter dependency**, so the domain seam stays headless and
/// platform-agnostic (Constitution II; enforced by the layer-boundary test). All
/// types are immutable, use value equality, and round-trip through JSON.
library;

/// An immutable width/height pair, in logical points.
class JetSize {
  /// Creates a size of [width] x [height] points.
  const JetSize(this.width, this.height);

  /// Reads a [JetSize] from its [toJson] map.
  factory JetSize.fromJson(Map<String, Object?> json) =>
      JetSize((json['w']! as num).toDouble(), (json['h']! as num).toDouble());

  /// Horizontal extent, in points.
  final double width;

  /// Vertical extent, in points.
  final double height;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{'w': width, 'h': height};

  @override
  bool operator ==(Object other) =>
      other is JetSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'JetSize($width, $height)';
}

/// An immutable (dx, dy) displacement, in logical points.
class JetOffset {
  /// Creates an offset of ([dx], [dy]) points.
  const JetOffset(this.dx, this.dy);

  /// Reads a [JetOffset] from its [toJson] map.
  factory JetOffset.fromJson(Map<String, Object?> json) => JetOffset(
      (json['dx']! as num).toDouble(), (json['dy']! as num).toDouble());

  /// Horizontal displacement, in points.
  final double dx;

  /// Vertical displacement, in points.
  final double dy;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{'dx': dx, 'dy': dy};

  @override
  bool operator ==(Object other) =>
      other is JetOffset && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'JetOffset($dx, $dy)';
}

/// Immutable inset distances for the four sides of a box, in logical points.
class JetEdgeInsets {
  /// Creates insets with explicit per-side values.
  const JetEdgeInsets({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Creates insets with the same [value] on every side.
  const JetEdgeInsets.all(double value)
      : left = value,
        top = value,
        right = value,
        bottom = value;

  /// Reads [JetEdgeInsets] from its [toJson] map.
  factory JetEdgeInsets.fromJson(Map<String, Object?> json) => JetEdgeInsets(
        left: (json['l']! as num).toDouble(),
        top: (json['t']! as num).toDouble(),
        right: (json['r']! as num).toDouble(),
        bottom: (json['b']! as num).toDouble(),
      );

  /// Inset from the left edge, in points.
  final double left;

  /// Inset from the top edge, in points.
  final double top;

  /// Inset from the right edge, in points.
  final double right;

  /// Inset from the bottom edge, in points.
  final double bottom;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() =>
      <String, Object?>{'l': left, 't': top, 'r': right, 'b': bottom};

  @override
  bool operator ==(Object other) =>
      other is JetEdgeInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'JetEdgeInsets($left, $top, $right, $bottom)';
}

/// An immutable axis-aligned rectangle: top-left at ([x], [y]) with [width] x
/// [height], all in logical points.
class JetRect {
  /// Creates a rectangle.
  const JetRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Reads a [JetRect] from its [toJson] map.
  factory JetRect.fromJson(Map<String, Object?> json) => JetRect(
        x: (json['x']! as num).toDouble(),
        y: (json['y']! as num).toDouble(),
        width: (json['w']! as num).toDouble(),
        height: (json['h']! as num).toDouble(),
      );

  /// The empty rectangle at the origin.
  static const JetRect zero = JetRect(x: 0, y: 0, width: 0, height: 0);

  /// Left edge, in points.
  final double x;

  /// Top edge, in points.
  final double y;

  /// Width, in points.
  final double width;

  /// Height, in points.
  final double height;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() =>
      <String, Object?>{'x': x, 'y': y, 'w': width, 'h': height};

  @override
  bool operator ==(Object other) =>
      other is JetRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'JetRect($x, $y, $width, $height)';
}

/// Immutable sizing bounds for `ElementRenderer.measure`: a maximum [maxWidth]
/// and [maxHeight] in logical points. Either may be [double.infinity]
/// (unbounded). Pure-Dart; mirrors the role of a layout constraint without any
/// `dart:ui` dependency.
class JetConstraints {
  /// Creates constraints; both axes default to unbounded.
  const JetConstraints({
    this.maxWidth = double.infinity,
    this.maxHeight = double.infinity,
  });

  /// Maximum width, in points (may be [double.infinity]).
  final double maxWidth;

  /// Maximum height, in points (may be [double.infinity]).
  final double maxHeight;

  /// Returns [size] with each axis clamped down to the corresponding max.
  JetSize constrain(JetSize size) => JetSize(
        size.width < maxWidth ? size.width : maxWidth,
        size.height < maxHeight ? size.height : maxHeight,
      );

  @override
  bool operator ==(Object other) =>
      other is JetConstraints &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(maxWidth, maxHeight);

  @override
  String toString() =>
      'JetConstraints(maxWidth: $maxWidth, maxHeight: $maxHeight)';
}
