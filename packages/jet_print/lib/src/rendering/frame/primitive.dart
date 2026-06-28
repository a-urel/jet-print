/// Positioned display-list primitives (spec 006): the WYSIWYG contract between
/// layout and paint. Pure-Dart geometry; each primitive carries its originating
/// element id for designer hit-testing.
library;

import 'dart:typed_data';

import '../../domain/elements/image_source.dart';
import '../../domain/geometry.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../text/text_measurer.dart';

/// A single positioned primitive on a page.
sealed class FramePrimitive {
  /// Creates a primitive bounded by [bounds] (page points), optionally tagged
  /// with the originating [elementId] and rotated by [rotation].
  const FramePrimitive(
      {required this.bounds, this.elementId, this.rotation = 0});

  /// Position and size, in page points.
  final JetRect bounds;

  /// The originating element's id, or null (e.g. chrome).
  final String? elementId;

  /// Clockwise rotation in radians, applied about [bounds]'s center by the
  /// paint layer. Default 0 (no rotation) — keeps existing frames byte-identical.
  final double rotation;
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
  bool operator ==(Object other) =>
      other is TextRunPrimitive &&
      other.bounds == bounds &&
      other.elementId == elementId &&
      other.rotation == rotation &&
      other.style == style &&
      other.fontFamily == fontFamily &&
      _listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(
      bounds, elementId, rotation, style, fontFamily, Object.hashAll(lines));

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
  bool operator ==(Object other) {
    if (other is! ImagePrimitive ||
        other.bounds != bounds ||
        other.elementId != elementId ||
        other.rotation != rotation ||
        other.fit != fit ||
        other.opacity != opacity ||
        other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
      bounds, elementId, rotation, fit, opacity, Object.hashAll(bytes));

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
  bool operator ==(Object other) =>
      other is LinePrimitive &&
      other.bounds == bounds &&
      other.elementId == elementId &&
      other.rotation == rotation &&
      other.start == start &&
      other.end == end &&
      other.color == color &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode =>
      Object.hash(bounds, elementId, rotation, start, end, color, strokeWidth);

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
  bool operator ==(Object other) =>
      other is RectPrimitive &&
      other.bounds == bounds &&
      other.elementId == elementId &&
      other.rotation == rotation &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode =>
      Object.hash(bounds, elementId, rotation, fill, stroke, strokeWidth);

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
  bool operator ==(Object other) =>
      other is PathPrimitive &&
      other.bounds == bounds &&
      other.elementId == elementId &&
      other.rotation == rotation &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth &&
      _listEquals(other.commands, commands);

  @override
  int get hashCode => Object.hash(bounds, elementId, rotation, fill, stroke,
      strokeWidth, Object.hashAll(commands));

  @override
  String toString() => 'PathPrimitive($bounds, ${commands.length} cmds)';
}

/// A single path instruction.
sealed class PathCommand {
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
  bool operator ==(Object other) => other is MoveTo && other.to == to;

  @override
  int get hashCode => Object.hash('MoveTo', to);

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
  bool operator ==(Object other) => other is LineTo && other.to == to;

  @override
  int get hashCode => Object.hash('LineTo', to);

  @override
  String toString() => 'LineTo($to)';
}

/// Close the current sub-path.
final class ClosePath extends PathCommand {
  /// Creates a close command.
  const ClosePath();

  @override
  bool operator ==(Object other) => other is ClosePath;

  @override
  int get hashCode => 'ClosePath'.hashCode;

  @override
  String toString() => 'ClosePath()';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
