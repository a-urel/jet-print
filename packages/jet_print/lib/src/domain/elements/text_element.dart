/// A static or (later) data-bound text element.
library;

import '../report_element.dart';

/// Renders [text] within its [bounds]. For this iteration [text] is a literal
/// string; expression binding arrives with the expression engine (spec 005).
class TextElement extends ReportElement {
  /// Creates a text element.
  const TextElement({
    required super.id,
    required super.bounds,
    required this.text,
  });

  /// The literal text to render.
  final String text;

  @override
  String get typeKey => 'text';

  @override
  bool operator ==(Object other) =>
      other is TextElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, bounds, text);

  @override
  String toString() => 'TextElement($id, "$text")';
}
