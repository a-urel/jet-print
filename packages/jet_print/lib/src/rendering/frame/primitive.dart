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

import 'dart:math' as math;
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
      {required this.bounds, this.elementId, this.rotation = 0, this.clip});

  /// Position and size, in page points.
  final JetRect bounds;

  /// The originating element's id, or null (e.g. chrome). Provenance only —
  /// see the library dartdoc for who actually reads it.
  final String? elementId;

  /// Clockwise rotation in radians, applied about [bounds]'s center by the
  /// paint layer. Default 0 (no rotation) — keeps existing frames byte-identical.
  final double rotation;

  /// An optional page-space rectangle the primitive is clipped to, or null for
  /// no clip. Applied by the paint layer *outside* [rotation], so the clip
  /// stays an upright page rectangle however the primitive itself turns.
  ///
  /// A per-primitive field rather than a begin/end pair, so the frame stays
  /// flat: no primitive depends on another to be drawn correctly.
  final JetRect? clip;

  /// The base fields every primitive's [props] must include — spread first.
  List<Object?> get baseProps => <Object?>[bounds, elementId, rotation, clip];
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
    super.clip,
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
    super.clip,
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
    this.dashPattern,
    super.elementId,
    super.rotation,
    super.clip,
  });

  /// Start point, in page points.
  final JetOffset start;

  /// End point, in page points.
  final JetOffset end;

  /// Stroke color.
  final JetColor color;

  /// Stroke width, in points.
  final double strokeWidth;

  /// Alternating dash and gap lengths in points, or null for a solid line.
  /// An odd-length pattern repeats itself, as in PDF and SVG.
  final List<double>? dashPattern;

  @override
  List<Object?> get props =>
      <Object?>[...baseProps, start, end, color, strokeWidth, dashPattern];

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
    super.clip,
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
    this.dashPattern,
    super.elementId,
    super.rotation,
    super.clip,
  });

  /// The path commands, in order.
  final List<PathCommand> commands;

  /// Fill color, or null.
  final JetColor? fill;

  /// Stroke color, or null.
  final JetColor? stroke;

  /// Stroke width, in points.
  final double strokeWidth;

  /// Alternating dash and gap lengths in points for the stroke, or null for a
  /// solid stroke. Never affects the fill.
  final List<double>? dashPattern;

  @override
  List<Object?> get props =>
      <Object?>[...baseProps, fill, stroke, strokeWidth, dashPattern, commands];

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

/// A circular arc about [center], continuing the current sub-path.
///
/// Angles are radians in page space (y down), so a positive [sweepAngle]
/// travels clockwise on screen. As in Flutter's `Path.arcTo`, a straight line
/// joins the current point to the arc's start when they differ.
final class ArcTo extends PathCommand {
  /// Creates an arc command.
  const ArcTo(this.center, this.radius, this.startAngle, this.sweepAngle);

  /// Centre of the circle, in page points.
  final JetOffset center;

  /// Circle radius, in points.
  final double radius;

  /// Start angle, in radians; 0 points right, pi/2 points down.
  final double startAngle;

  /// Signed sweep, in radians.
  final double sweepAngle;

  /// The arc cut into sub-arcs of at most half a turn each, in order, with the
  /// same total sweep and direction.
  ///
  /// Backends that replay an arc through `Path.arcTo` use this rather than the
  /// whole sweep: `arcTo` draws nothing for a sweep that is a full turn, which
  /// would make a disc vanish on screen while the PDF still drew it.
  List<({double start, double sweep})> get halfTurnParts {
    final int n = (sweepAngle.abs() / math.pi).ceil().clamp(1, 1000);
    final double step = sweepAngle / n;
    return <({double start, double sweep})>[
      for (int i = 0; i < n; i++) (start: startAngle + step * i, sweep: step),
    ];
  }

  @override
  List<Object?> get props => <Object?>[center, radius, startAngle, sweepAngle];

  @override
  String toString() => 'ArcTo($center, r: $radius, $startAngle + $sweepAngle)';
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
