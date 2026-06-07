/// A static or (later) data-bound text element.
library;

import '../report_element.dart';
import '../styles/text_style.dart';

/// Renders [text] within its [bounds] using [style]. For this iteration [text]
/// is a literal string; expression binding arrives with the expression engine
/// (spec 005).
class TextElement extends ReportElement {
  /// Creates a text element.
  const TextElement({
    required super.id,
    required super.bounds,
    required this.text,
    this.style = JetTextStyle.fallback,
  });

  /// The literal text to render.
  final String text;

  /// Text appearance.
  final JetTextStyle style;

  @override
  String get typeKey => 'text';

  @override
  bool operator ==(Object other) =>
      other is TextElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.text == text &&
      other.style == style;

  @override
  int get hashCode => Object.hash(id, bounds, text, style);

  @override
  String toString() => 'TextElement($id, "$text")';
}
