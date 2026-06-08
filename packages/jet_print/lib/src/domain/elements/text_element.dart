/// A static or (later) data-bound text element.
library;

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
  });

  /// The literal text to render (the resolved value after Fill, or the authored
  /// literal when [expression] is null).
  final String text;

  /// Text appearance.
  final JetTextStyle style;

  /// Optional data-binding expression (005a). Null for static text.
  final String? expression;

  @override
  String get typeKey => 'text';

  @override
  bool operator ==(Object other) =>
      other is TextElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.text == text &&
      other.style == style &&
      other.expression == expression;

  @override
  int get hashCode => Object.hash(id, bounds, text, style, expression);

  @override
  String toString() => 'TextElement($id, "$text"'
      '${expression == null ? '' : ', expr: "$expression"'})';
}
