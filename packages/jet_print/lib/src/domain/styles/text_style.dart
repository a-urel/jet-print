/// Text styling for the report model (pure Dart, no `dart:ui`).
library;

import 'color.dart';

/// Horizontal text alignment within an element's bounds.
enum JetTextAlign { left, center, right, justify }

/// Coarse font weight; mapped to concrete OS weights by the renderer.
enum JetFontWeight { normal, medium, semiBold, bold }

/// Immutable text appearance. JSON omits [fontFamily] when null and
/// [underline] when false; other fields are always present.
class JetTextStyle {
  /// Creates a text style; every field has a default (see [fallback]).
  const JetTextStyle({
    this.fontFamily,
    this.fontSize = 12,
    this.weight = JetFontWeight.normal,
    this.italic = false,
    this.underline = false,
    this.color = JetColor.black,
    this.align = JetTextAlign.left,
  });

  /// Reads a [JetTextStyle] from its [toJson] map. `underline` is an additive
  /// 021 field: a pre-021 map has no key (and a malformed value is not `true`),
  /// so both read as false — older documents load unchanged.
  factory JetTextStyle.fromJson(Map<String, Object?> json) => JetTextStyle(
        fontFamily: json['fontFamily'] as String?,
        fontSize: (json['fontSize']! as num).toDouble(),
        weight: JetFontWeight.values.byName(json['weight']! as String),
        italic: json['italic']! as bool,
        underline: json['underline'] == true,
        color: JetColor.fromJson(json['color']! as String),
        align: JetTextAlign.values.byName(json['align']! as String),
      );

  /// The default style (12pt, normal, upright, black, left-aligned).
  static const JetTextStyle fallback = JetTextStyle();

  /// Sentinel distinguishing an omitted [copyWith] argument from an explicit
  /// null (only [fontFamily] is nullable, so only it needs one).
  static const Object _unset = Object();

  /// Font family name, or null to use the renderer's default font.
  final String? fontFamily;

  /// Font size, in points.
  final double fontSize;

  /// Font weight.
  final JetFontWeight weight;

  /// Whether the text is italic.
  final bool italic;

  /// Whether the text is underlined.
  final bool underline;

  /// Text color.
  final JetColor color;

  /// Horizontal alignment.
  final JetTextAlign align;

  /// A copy with the given fields replaced.
  ///
  /// [fontFamily] is sentinel-based because it is nullable: omitting it
  /// preserves the current family, while an explicit `null` clears it (back to
  /// the renderer's default font) — two different edits.
  JetTextStyle copyWith({
    Object? fontFamily = _unset,
    double? fontSize,
    JetFontWeight? weight,
    bool? italic,
    bool? underline,
    JetColor? color,
    JetTextAlign? align,
  }) =>
      JetTextStyle(
        fontFamily: identical(fontFamily, _unset)
            ? this.fontFamily
            : fontFamily as String?,
        fontSize: fontSize ?? this.fontSize,
        weight: weight ?? this.weight,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        color: color ?? this.color,
        align: align ?? this.align,
      );

  /// Serializes to a JSON-safe map (omitting [fontFamily] when null and
  /// [underline] when false — the pre-021 wire shape stays byte-identical).
  Map<String, Object?> toJson() => <String, Object?>{
        if (fontFamily != null) 'fontFamily': fontFamily,
        'fontSize': fontSize,
        'weight': weight.name,
        'italic': italic,
        if (underline) 'underline': true,
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
      other.underline == underline &&
      other.color == color &&
      other.align == align;

  @override
  int get hashCode => Object.hash(
      fontFamily, fontSize, weight, italic, underline, color, align);

  @override
  String toString() =>
      'JetTextStyle($fontSize, ${weight.name}${underline ? ', underline' : ''})';
}
