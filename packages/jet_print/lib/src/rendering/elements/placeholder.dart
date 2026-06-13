/// A shared visible-placeholder primitive (spec 007a): an outline rect plus a
/// small label. Backs the image-missing, barcode, and unknown-element cases so a
/// renderer never leaves an element blank (render-don't-crash).
library;

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
