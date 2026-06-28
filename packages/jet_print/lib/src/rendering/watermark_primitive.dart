/// Builds the single positioned primitive for a page watermark (pure: no
/// `dart:ui`). Centered on the full page rect, rotated by the watermark angle,
/// dimmed by its opacity. Text takes precedence when both text and image are set.
library;

import 'dart:math' as math;

import '../domain/geometry.dart';
import '../domain/page_format.dart';
import '../domain/styles/color.dart';
import '../domain/styles/text_style.dart';
import '../domain/watermark.dart';
import 'frame/primitive.dart';
import 'text/text_measurer.dart';

/// Returns the watermark primitive for [page], or null when nothing should be
/// drawn (opacity 0, empty text, or no content). The result is identical for
/// every page (the page size is constant), so callers build it once.
FramePrimitive? buildWatermarkPrimitive(
    Watermark wm, PageFormat page, TextMeasurer measurer) {
  if (wm.opacity <= 0) return null;
  final double radians = wm.angleDegrees * math.pi / 180;

  final String? text = wm.text;
  if (text != null && text.trim().isNotEmpty) {
    final MeasuredText m = measurer.measure(text, wm.textStyle);
    final double height =
        m.lines.isEmpty ? 0 : m.lines.last.top + m.lines.last.height;
    final JetColor faded = _scaleAlpha(wm.textStyle.color, wm.opacity);
    return TextRunPrimitive(
      bounds: JetRect(
          x: 0,
          y: (page.height - height) / 2,
          width: page.width,
          height: height),
      lines: m.lines,
      style: wm.textStyle.copyWith(color: faded, align: JetTextAlign.center),
      fontFamily: m.fontFamily,
      rotation: radians,
    );
  }

  final image = wm.imageBytes;
  if (image != null && image.isNotEmpty) {
    final double w = page.width * 0.5;
    final double h = page.height * 0.5;
    return ImagePrimitive(
      bounds: JetRect(
          x: (page.width - w) / 2,
          y: (page.height - h) / 2,
          width: w,
          height: h),
      bytes: image,
      fit: wm.imageFit,
      opacity: wm.opacity,
      rotation: radians,
    );
  }
  return null;
}

JetColor _scaleAlpha(JetColor c, double factor) {
  final int a = (((c.argb >> 24) & 0xff) * factor).round().clamp(0, 255);
  return JetColor((a << 24) | (c.argb & 0x00ffffff));
}
