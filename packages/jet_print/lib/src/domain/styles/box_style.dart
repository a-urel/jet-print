/// Fill/stroke styling for shapes and boxes (pure Dart).
library;

import 'color.dart';

/// Immutable box appearance: an optional [fill], an optional [stroke], and a
/// [strokeWidth] (points). JSON omits null fill/stroke.
class JetBoxStyle {
  /// Creates a box style.
  const JetBoxStyle({this.fill, this.stroke, this.strokeWidth = 1.0});

  /// Reads a [JetBoxStyle] from its [toJson] map.
  factory JetBoxStyle.fromJson(Map<String, Object?> json) => JetBoxStyle(
        fill: json['fill'] is String
            ? JetColor.fromJson(json['fill']! as String)
            : null,
        stroke: json['stroke'] is String
            ? JetColor.fromJson(json['stroke']! as String)
            : null,
        strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1.0,
      );

  /// No fill, no stroke, unit stroke width.
  static const JetBoxStyle none = JetBoxStyle();

  /// Sentinel distinguishing an omitted [copyWith] argument from an explicit
  /// null — both [fill] and [stroke] are nullable, and "clear to no fill /
  /// no outline" must be expressible (021 / FR-007, FR-008).
  static const Object _unset = Object();

  /// Fill color, or null for no fill.
  final JetColor? fill;

  /// Stroke (border/line) color, or null for no stroke.
  final JetColor? stroke;

  /// Stroke width, in points.
  final double strokeWidth;

  /// A copy with the given fields replaced.
  ///
  /// [fill] and [stroke] are sentinel-based: omitting one preserves the
  /// current color, while an explicit `null` clears it ("no fill" /
  /// "no outline") — two different edits.
  JetBoxStyle copyWith({
    Object? fill = _unset,
    Object? stroke = _unset,
    double? strokeWidth,
  }) =>
      JetBoxStyle(
        fill: identical(fill, _unset) ? this.fill : fill as JetColor?,
        stroke: identical(stroke, _unset) ? this.stroke : stroke as JetColor?,
        strokeWidth: strokeWidth ?? this.strokeWidth,
      );

  /// Serializes to a JSON-safe map (omitting null fill/stroke).
  Map<String, Object?> toJson() => <String, Object?>{
        if (fill != null) 'fill': fill!.toJson(),
        if (stroke != null) 'stroke': stroke!.toJson(),
        'strokeWidth': strokeWidth,
      };

  @override
  bool operator ==(Object other) =>
      other is JetBoxStyle &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(fill, stroke, strokeWidth);

  @override
  String toString() =>
      'JetBoxStyle(fill: $fill, stroke: $stroke, $strokeWidth)';
}
