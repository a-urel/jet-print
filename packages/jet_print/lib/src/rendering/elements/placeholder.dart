/// A shared visible-placeholder primitive (spec 007a): an outline rect plus a
/// small label. Backs the image-missing, barcode, and unknown-element cases so a
/// renderer never leaves an element blank (render-don't-crash).
library;

import 'dart:math' as math;

import '../../domain/geometry.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../frame/frame_builder.dart';
import '../frame/primitive.dart';
import '../text/text_measurer.dart';
import 'render_context.dart';

/// A muted grey for placeholder outlines and labels.
const JetColor _placeholderColor = JetColor(0xFF999999);

/// The label style: small, muted, left-aligned.
const JetTextStyle _placeholderStyle =
    JetTextStyle(fontSize: 8, color: _placeholderColor);

/// Appends an outline [RectPrimitive] over [bounds] followed by a measured
/// [label] [TextRunPrimitive], both tagged with [elementId].
///
/// [color] tints the outline and the label — the barcode placeholder passes
/// the element's bar color so a color edit is visible and WYSIWYG-consistent
/// before real symbology rendering lands (021 / research §8). Omitted, the
/// placeholder keeps its muted grey (image-missing, unknown element).
void emitPlaceholder(
  FrameBuilder out,
  JetRect bounds,
  String label,
  RenderContext ctx, {
  String? elementId,
  JetColor color = _placeholderColor,
}) {
  out.add(RectPrimitive(
    bounds: bounds,
    stroke: color,
    elementId: elementId,
  ));
  final JetTextStyle style = color == _placeholderColor
      ? _placeholderStyle
      : JetTextStyle(fontSize: _placeholderStyle.fontSize, color: color);
  final MeasuredText m =
      ctx.measurer.measure(label, style, maxWidth: bounds.width);
  out.add(TextRunPrimitive(
    bounds: bounds,
    lines: m.lines,
    style: style,
    fontFamily: m.fontFamily,
    elementId: elementId,
  ));
}

/// Appends an image-glyph placeholder over [bounds]: the full-bounds outline
/// [RectPrimitive] (the element's extent), plus — when the element is large
/// enough to be legible — a centered picture-frame glyph (frame rect + a filled
/// "mountain" triangle + a small filled "sun" octagon), all in [_placeholderColor]
/// and tagged with [elementId].
///
/// Used for the source-less image case (designer canvas, unresolved field, or
/// URL — the library does no network I/O), in place of the text [emitPlaceholder].
/// Composed from existing primitives so it paints identically on canvas and PDF.
void emitImagePlaceholder(
  FrameBuilder out,
  JetRect bounds, {
  String? elementId,
}) {
  // Full-bounds element outline — the same affordance the text placeholder gave.
  out.add(RectPrimitive(
    bounds: bounds,
    stroke: _placeholderColor,
    elementId: elementId,
  ));

  final double side =
      (math.min(bounds.width, bounds.height) * 0.55).clamp(0.0, 28.0);
  if (side < 8.0) return; // too small for a legible glyph

  final double cx = bounds.x + bounds.width / 2;
  final double cy = bounds.y + bounds.height / 2;
  final double left = cx - side / 2;
  final double top = cy - side / 2;
  final double right = cx + side / 2;
  final double bottom = cy + side / 2;
  final JetRect square =
      JetRect(x: left, y: top, width: side, height: side);

  // Picture frame.
  out.add(RectPrimitive(
    bounds: square,
    stroke: _placeholderColor,
    elementId: elementId,
  ));

  // Sun: a small filled octagon in the upper-left quadrant (the primitive set
  // has no circle, so approximate with an 8-gon).
  final double sunR = side * 0.12;
  final double sunCx = left + side * 0.30;
  final double sunCy = top + side * 0.30;
  final List<PathCommand> sun = <PathCommand>[];
  for (int i = 0; i < 8; i++) {
    final double a = i * math.pi / 4;
    final JetOffset p =
        JetOffset(sunCx + sunR * math.cos(a), sunCy + sunR * math.sin(a));
    sun.add(i == 0 ? MoveTo(p) : LineTo(p));
  }
  sun.add(const ClosePath());
  out.add(PathPrimitive(
    bounds: square,
    commands: sun,
    fill: _placeholderColor,
    elementId: elementId,
  ));

  // Mountain: a filled triangle resting on the frame's lower edge.
  out.add(PathPrimitive(
    bounds: square,
    commands: <PathCommand>[
      MoveTo(JetOffset(left + side * 0.15, bottom - side * 0.15)),
      LineTo(JetOffset(left + side * 0.55, top + side * 0.45)),
      LineTo(JetOffset(right - side * 0.15, bottom - side * 0.15)),
      const ClosePath(),
    ],
    fill: _placeholderColor,
    elementId: elementId,
  ));
}
