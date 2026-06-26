/// A vector shape element — a line, a rectangle, or one of the closed forms.
library;

import '../geometry.dart';
import '../report_element.dart';
import '../styles/box_style.dart';

/// The form of a [ShapeElement].
///
/// [line] and [rectangle] are special-cased by the renderer
/// ([LinePrimitive]/[RectPrimitive]); every other value is an inscribed polygon
/// produced by the shared `shapePath` geometry and drawn as a single
/// `PathPrimitive`, so canvas, preview, and export agree by construction.
///
/// The values serialize by [name], so the order here is irrelevant to the wire
/// format and the six closed forms are purely additive — a report authored
/// before they existed loads byte-for-byte unchanged.
enum ShapeKind {
  /// A straight line across the element's [ReportElement.bounds] box.
  line,

  /// A rectangle filling the element's [ReportElement.bounds] box.
  rectangle,

  /// An ellipse inscribed in the bounds (a high-segment polygon).
  ellipse,

  /// A triangle: apex at top-centre, base across the bottom edge.
  triangle,

  /// A diamond touching the four edge midpoints.
  diamond,

  /// A regular, point-up pentagon inscribed in the bounds.
  pentagon,

  /// A regular, point-up hexagon inscribed in the bounds.
  hexagon,

  /// A five-point, point-up star inscribed in the bounds.
  star,
}

/// A vector shape ([kind]) drawn within [bounds] using [style]. For a
/// [ShapeKind.line], [flipDiagonal] selects the bottom-left→top-right diagonal
/// instead of the default top-left→bottom-right.
///
/// When a report serialized by a *newer* version names a [kind] this version
/// does not recognize, the codec loads it as a [ShapeKind.rectangle] (a safe
/// render default) while preserving the original form name in [unknownForm], so
/// re-saving does not discard it (a lossless forward-compatible round-trip). A
/// deliberate gallery pick clears [unknownForm].
class ShapeElement extends ReportElement {
  /// Creates a shape element.
  const ShapeElement({
    required super.id,
    required super.bounds,
    required this.kind,
    this.style = JetBoxStyle.none,
    this.flipDiagonal = false,
    this.unknownForm,
    super.name,
  });

  /// The form this shape draws.
  final ShapeKind kind;

  /// Fill/stroke appearance.
  final JetBoxStyle style;

  /// For lines only: use the opposite diagonal when true.
  final bool flipDiagonal;

  /// The original serialized form name when [kind] was unrecognized on load,
  /// else null. Non-null only when [kind] is [ShapeKind.rectangle] (the safe
  /// render default for an unknown form); a deliberate pick clears it.
  final String? unknownForm;

  /// Returns a copy with the named fields replaced and the rest preserved.
  ///
  /// [unknownForm] cannot be passed here because Dart's `copyWith` cannot tell
  /// "leave it" from "set it to null"; pass [clearUnknownForm] `true` to null it
  /// — what a deliberate form pick does, since choosing a known form supersedes
  /// any preserved unknown one.
  ShapeElement copyWith({
    JetRect? bounds,
    ShapeKind? kind,
    JetBoxStyle? style,
    bool? flipDiagonal,
    bool clearUnknownForm = false,
    String? name,
  }) =>
      ShapeElement(
        id: id,
        bounds: bounds ?? this.bounds,
        kind: kind ?? this.kind,
        style: style ?? this.style,
        flipDiagonal: flipDiagonal ?? this.flipDiagonal,
        unknownForm: clearUnknownForm ? null : unknownForm,
        name: name ?? this.name,
      );

  @override
  String get typeKey => 'shape';

  @override
  ShapeElement withBounds(JetRect bounds) => ShapeElement(
        id: id,
        bounds: bounds,
        kind: kind,
        style: style,
        flipDiagonal: flipDiagonal,
        unknownForm: unknownForm,
        name: name,
      );

  @override
  ShapeElement withName(String? name) => ShapeElement(
        id: id,
        bounds: bounds,
        kind: kind,
        style: style,
        flipDiagonal: flipDiagonal,
        unknownForm: unknownForm,
        name: name,
      );

  @override
  bool operator ==(Object other) =>
      other is ShapeElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.kind == kind &&
      other.style == style &&
      other.flipDiagonal == flipDiagonal &&
      other.unknownForm == unknownForm &&
      other.name == name;

  @override
  int get hashCode =>
      Object.hash(id, bounds, kind, style, flipDiagonal, unknownForm, name);

  @override
  String toString() => unknownForm == null
      ? 'ShapeElement($id, ${kind.name})'
      : 'ShapeElement($id, ${kind.name}, unknownForm: $unknownForm)';
}
