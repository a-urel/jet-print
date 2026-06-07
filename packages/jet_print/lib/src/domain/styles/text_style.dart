/// Text styling for the report model (pure Dart, no `dart:ui`).
library;

import 'color.dart';

/// Horizontal text alignment within an element's bounds.
enum JetTextAlign { left, center, right, justify }

/// Coarse font weight; mapped to concrete OS weights by the renderer.
enum JetFontWeight { normal, medium, semiBold, bold }

/// Immutable text appearance. JSON omits [fontFamily] when null; other fields
/// are always present.
class JetTextStyle {
  /// Creates a text style; every field has a default (see [fallback]).
  const JetTextStyle({
    this.fontFamily,
    this.fontSize = 12,
    this.weight = JetFontWeight.normal,
    this.italic = false,
    this.color = JetColor.black,
    this.align = JetTextAlign.left,
  });

  /// Reads a [JetTextStyle] from its [toJson] map.
  factory JetTextStyle.fromJson(Map<String, Object?> json) => JetTextStyle(
        fontFamily: json['fontFamily'] as String?,
        fontSize: (json['fontSize']! as num).toDouble(),
        weight: JetFontWeight.values.byName(json['weight']! as String),
        italic: json['italic']! as bool,
        color: JetColor.fromJson(json['color']! as String),
        align: JetTextAlign.values.byName(json['align']! as String),
      );

  /// The default style (12pt, normal, upright, black, left-aligned).
  static const JetTextStyle fallback = JetTextStyle();

  /// Font family name, or null to use the renderer's default font.
  final String? fontFamily;

  /// Font size, in points.
  final double fontSize;

  /// Font weight.
  final JetFontWeight weight;

  /// Whether the text is italic.
  final bool italic;

  /// Text color.
  final JetColor color;

  /// Horizontal alignment.
  final JetTextAlign align;

  /// Serializes to a JSON-safe map (omitting [fontFamily] when null).
  Map<String, Object?> toJson() => <String, Object?>{
        if (fontFamily != null) 'fontFamily': fontFamily,
        'fontSize': fontSize,
        'weight': weight.name,
        'italic': italic,
        'color': color.toJson(),
        'align': align.name,
      };

  @override
  bool operator ==(Object other) =>
      other is JetTextStyle &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.weight == weight &&
      other.italic == italic &&
      other.color == color &&
      other.align == align;

  @override
  int get hashCode =>
      Object.hash(fontFamily, fontSize, weight, italic, color, align);

  @override
  String toString() => 'JetTextStyle($fontSize, ${weight.name})';
}
