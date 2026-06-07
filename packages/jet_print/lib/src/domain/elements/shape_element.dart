/// A line or rectangle shape element.
library;

import '../report_element.dart';
import '../styles/box_style.dart';

/// The kind of [ShapeElement].
enum ShapeKind {
  /// A straight line across the element's [ReportElement.bounds] box.
  line,

  /// A rectangle filling the element's [ReportElement.bounds] box.
  rectangle,
}

/// A vector shape ([kind]) drawn within [bounds] using [style]. For a
/// [ShapeKind.line], [flipDiagonal] selects the bottom-left→top-right diagonal
/// instead of the default top-left→bottom-right.
class ShapeElement extends ReportElement {
  /// Creates a shape element.
  const ShapeElement({
    required super.id,
    required super.bounds,
    required this.kind,
    this.style = JetBoxStyle.none,
    this.flipDiagonal = false,
  });

  /// Whether this is a line or a rectangle.
  final ShapeKind kind;

  /// Fill/stroke appearance.
  final JetBoxStyle style;

  /// For lines only: use the opposite diagonal when true.
  final bool flipDiagonal;

  @override
  String get typeKey => 'shape';

  @override
  bool operator ==(Object other) =>
      other is ShapeElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.kind == kind &&
      other.style == style &&
      other.flipDiagonal == flipDiagonal;

  @override
  int get hashCode => Object.hash(id, bounds, kind, style, flipDiagonal);

  @override
  String toString() => 'ShapeElement($id, ${kind.name})';
}
