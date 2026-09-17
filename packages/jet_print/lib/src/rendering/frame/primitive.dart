/// Positioned display-list primitives: the WYSIWYG contract between
/// layout and paint. Pure-Dart geometry; each primitive carries its originating
/// element id as provenance.
///
/// Nothing under `lib/` reads [FramePrimitive.elementId] — designer
/// hit-testing goes through `DesignTimeLayout.elementRect`
/// (`designer/canvas/hit_testing.dart`), never through the display list. The
/// id is consumed by the rendering tests, which use it to assert *which*
/// element produced a given primitive; keep emitting it.
library;

import 'dart:typed_data';

import '../../domain/elements/image_source.dart';
import '../../domain/geometry.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../../domain/value_equality.dart';
import '../text/text_measurer.dart';

/// A single positioned primitive on a page.
sealed class FramePrimitive with ValueEquality {
  /// Creates a primitive bounded by [bounds] (page points), optionally tagged
  /// with the originating [elementId] and rotated by [rotation].
  const FramePrimitive(
      {required this.bounds, this.elementId, this.rotation = 0});

  /// Position and size, in page points.
  final JetRect bounds;

  /// The originating element's id, or null (e.g. chrome). Provenance only —
  /// see the library dartdoc for who actually reads it.
  final String? elementId;

  /// Clockwise rotation in radians, applied about [bounds]'s center by the
  /// paint layer. Default 0 (no rotation) — keeps existing frames byte-identical.
  final double rotation;

  /// The base fields every primitive's [props] must include — spread first.
  List<Object?> get baseProps => <Object?>[bounds, elementId, rotation];
}

/// Pre-broken text: the measurer's [lines] drawn without re-wrapping.
final class TextRunPrimitive extends FramePrimitive {
  /// Creates a text run.
  const TextRunPrimitive({
    required super.bounds,
    required this.lines,
    required this.style,
    required this.fontFamily,
    super.elementId,
    super.rotation,
  });

  /// Laid-out lines (the painter never re-wraps these).
  final List<TextLine> lines;

  /// Text appearance (color/size/weight/italic/align).
  final JetTextStyle style;

  /// The resolved font family the painter must render with.
  final String fontFamily;

  @override
  List<Object?> get props => <Object?>[...baseProps, style, fontFamily, lines];

  @override
  String toString() =>
      'TextRunPrimitive($bounds, lines: ${lines.length}, "$fontFamily")';
}

/// A raster image; [bytes] are encoded (PNG/JPEG), decoded by the painter.
final class ImagePrimitive extends FramePrimitive {
  /// Creates an image primitive.
  const ImagePrimitive({
    required super.bounds,
    required this.bytes,
    this.fit = JetBoxFit.contain,
    this.opacity = 1.0,
    super.elementId,
    super.rotation,
  });

  /// Encoded image bytes.
  final Uint8List bytes;

  /// How the image fills [bounds].
  final JetBoxFit fit;

  /// 0..1 constant opacity applied when drawing. Default 1.0 (opaque).
  final double opacity;

  @override
  List<Object?> get props => <Object?>[...baseProps, fit, opacity, bytes];

  @override
  String toString() => 'ImagePrimitive($bounds, ${bytes.length}B, $fit)';
}

/// A straight stroked line from [start] to [end].
final class LinePrimitive extends FramePrimitive {
  /// Creates a line primitive.
  const LinePrimitive({
    required super.bounds,
    required this.start,
    required this.end,
    required this.color,
    this.strokeWidth = 1.0,
    super.elementId,
    super.rotation,
  });

  /// Start point, in page points.
  final JetOffset start;

  /// End point, in page points.
  final JetOffset end;

  /// Stroke color.
  final JetColor color;

  /// Stroke width, in points.
  final double strokeWidth;

  @override
  List<Object?> get props =>
      <Object?>[...baseProps, start, end, color, strokeWidth];

  @override
  String toString() => 'LinePrimitive($start -> $end, $color)';
}

/// A rectangle with optional [fill] and/or [stroke].
final class RectPrimitive extends FramePrimitive {
  /// Creates a rectangle primitive.
  const RectPrimitive({
    required super.bounds,
    this.fill,
    this.stroke,
    this.strokeWidth = 1.0,
    super.elementId,
    super.rotation,
  });

  /// Fill color, or null for no fill.
  final JetColor? fill;

  /// Stroke color, or null for no stroke.
  final JetColor? stroke;

  /// Stroke width, in points.
  final double strokeWidth;

  @override
  List<Object?> get props => <Object?>[...baseProps, fill, stroke, strokeWidth];

  @override
  String toString() => 'RectPrimitive($bounds, fill: $fill, stroke: $stroke)';
}

/// A polyline/polygon path with optional [fill] and/or [stroke].
final class PathPrimitive extends FramePrimitive {
  /// Creates a path primitive.
  const PathPrimitive({
    required super.bounds,
    required this.commands,
    this.fill,
    this.stroke,
    this.strokeWidth = 1.0,
    super.elementId,
    super.rotation,
  });

  /// The path commands, in order.
  final List<PathCommand> commands;

  /// Fill color, or null.
  final JetColor? fill;

  /// Stroke color, or null.
  final JetColor? stroke;

  /// Stroke width, in points.
  final double strokeWidth;

  @override
  List<Object?> get props =>
      <Object?>[...baseProps, fill, stroke, strokeWidth, commands];

  @override
  String toString() => 'PathPrimitive($bounds, ${commands.length} cmds)';
}

/// A single path instruction.
sealed class PathCommand with ValueEquality {
  /// Const base constructor.
  const PathCommand();
}

/// Move the pen to [to] without drawing.
final class MoveTo extends PathCommand {
  /// Creates a move command.
  const MoveTo(this.to);

  /// Target point.
  final JetOffset to;

  @override
  List<Object?> get props => <Object?>[to];

  @override
  String toString() => 'MoveTo($to)';
}

/// Draw a line to [to].
final class LineTo extends PathCommand {
  /// Creates a line command.
  const LineTo(this.to);

  /// Target point.
  final JetOffset to;

  @override
  List<Object?> get props => <Object?>[to];

  @override
  String toString() => 'LineTo($to)';
}

/// Close the current sub-path.
final class ClosePath extends PathCommand {
  /// Creates a close command.
  const ClosePath();

  @override
  List<Object?> get props => const <Object?>[];

  @override
  String toString() => 'ClosePath()';
}
