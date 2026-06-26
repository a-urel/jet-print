/// A static or (later) data-bound text element.
library;

import '../bool_property.dart';
import '../geometry.dart';
import '../report_element.dart';
import '../styles/text_style.dart';

/// Renders [text] within its [bounds] using [style]. For this iteration [text]
/// is a literal string; expression binding arrives with the expression engine
/// (spec 005).
class TextElement extends ReportElement {
  /// Creates a text element. [expression] (005a syntax), when non-null, is
  /// evaluated per row by Fill (007b) and replaces [text]; when null the literal
  /// [text] is used.
  const TextElement({
    required super.id,
    required super.bounds,
    required this.text,
    this.style = JetTextStyle.fallback,
    this.expression,
    this.format,
    super.name,
    super.visible,
  });

  /// The literal text to render (the resolved value after Fill, or the authored
  /// literal when [expression] is null).
  final String text;

  /// Text appearance.
  final JetTextStyle style;

  /// Optional data-binding expression (005a). Null for static text.
  final String? expression;

  /// Optional display format (013) — an ICU number/date pattern applied to the
  /// resolved value at render time. Null/empty means the value is shown as-is.
  final String? format;

  @override
  String get typeKey => 'text';

  /// Returns a copy with the given fields replaced; all others (incl.
  /// [expression] and [format]) are preserved (FR-019 / FR-025 / 013).
  TextElement copyWith(
          {String? text,
          JetTextStyle? style,
          JetRect? bounds,
          String? name,
          BoolProperty? visible}) =>
      TextElement(
        id: id,
        bounds: bounds ?? this.bounds,
        text: text ?? this.text,
        style: style ?? this.style,
        expression: expression,
        format: format,
        name: name ?? this.name,
        visible: visible ?? this.visible,
      );

  @override
  TextElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  TextElement withName(String? name) => TextElement(
        id: id,
        bounds: bounds,
        text: text,
        style: style,
        expression: expression,
        format: format,
        name: name,
        visible: visible,
      );

  @override
  TextElement withVisible(BoolProperty visible) => TextElement(
        id: id,
        bounds: bounds,
        text: text,
        style: style,
        expression: expression,
        format: format,
        name: name,
        visible: visible,
      );

  @override
  bool operator ==(Object other) =>
      other is TextElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.text == text &&
      other.style == style &&
      other.expression == expression &&
      other.format == format &&
      other.name == name &&
      other.visible == visible;

  @override
  int get hashCode =>
      Object.hash(id, bounds, text, style, expression, format, name, visible);

  @override
  String toString() => 'TextElement($id, "$text"'
      '${expression == null ? '' : ', expr: "$expression"'}'
      '${format == null ? '' : ', fmt: "$format"'})';
}
