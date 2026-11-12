/// JP0 spike: converts a jet_charts_core layout into frame primitives, so the
/// canvas, preview, PNG and PDF keep drawing one recorded picture.
///
/// Not wired into any renderer. What the frame cannot express yet is counted in
/// [ChartConversionGaps] rather than hidden.
library;

import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart' as core;

import '../../../domain/geometry.dart';
import '../../../domain/styles/color.dart';
import '../../../domain/styles/text_style.dart';
import '../../frame/primitive.dart';
import '../../text/font_registry.dart';
import '../../text/text_measurer.dart';

/// Adapts the engine's [TextMeasurer] to jet_charts_core's, so a chart is laid
/// out with the very font bytes the PDF embeds.
class ChartEngineMeasurer implements core.TextMeasurer {
  /// Creates the adapter over [_measurer].
  const ChartEngineMeasurer(this._measurer);

  final TextMeasurer _measurer;

  @override
  core.ChartSize measure(String text, core.ChartTextStyle style) {
    final MeasuredText m = _measurer.measure(text, _jetStyle(style));
    return core.ChartSize(m.size.width, m.size.height);
  }
}

JetTextStyle _jetStyle(core.ChartTextStyle s) => JetTextStyle(
      fontFamily:
          s.fontFamily.isEmpty ? FontRegistry.defaultFamily : s.fontFamily,
      fontSize: s.size,
      weight: s.bold ? JetFontWeight.bold : JetFontWeight.normal,
      color: _color(s.color),
    );

JetColor _color(core.ChartColor c) => JetColor(0xFF000000 | c.rgb);

/// What the converter could not express in the frame. Counts, per conversion.
class ChartConversionGaps {
  /// Arcs turned into polylines.
  int arcsFlattened = 0;

  /// Clip regions whose children were drawn unclipped.
  int clipsDropped = 0;

  /// Dashed paths drawn solid.
  int dashesDropped = 0;

  /// Translucent fills pre-blended with white.
  int opacityBlended = 0;

  @override
  String toString() => 'gaps(arcsFlattened: $arcsFlattened, '
      'clips: $clipsDropped, dashes: $dashesDropped, '
      'opacityBlended: $opacityBlended)';
}

/// The frame primitives of one chart and what was lost converting it.
class ChartFrameResult {
  /// Creates a result.
  const ChartFrameResult(this.primitives, this.gaps, this.layout);

  /// In paint order, in page coordinates.
  final List<FramePrimitive> primitives;

  /// What the frame could not express.
  final ChartConversionGaps gaps;

  /// The core layout, kept for inspection.
  final core.ChartLayout layout;
}

/// A report theme: the engine's default font and the element palette.
core.ChartTheme reportChartTheme(List<JetColor> palette) =>
    core.ChartTheme.fromColors(
      palette: <core.ChartColor>[
        for (final JetColor c in palette)
          core.ChartColor.rgb(c.argb & 0xFFFFFF),
      ],
      fontFamily: FontRegistry.defaultFamily,
      text: core.ChartColor.rgb(0x333333),
      background: core.ChartColor.rgb(0xFFFFFF),
      fontSize: 8,
    );

/// Lays [chart] out in [bounds] and converts it to frame primitives.
ChartFrameResult chartToFrame(
  core.Chart chart, {
  required JetRect bounds,
  required TextMeasurer measurer,
  core.ChartTheme? theme,
  String? elementId,
}) {
  final core.ChartTheme t = theme ??
      reportChartTheme(const <JetColor>[
        JetColor(0xFF4F8DF7),
        JetColor(0xFFF7894F),
        JetColor(0xFF4FB76B),
        JetColor(0xFFB74F9E),
        JetColor(0xFFE0C341),
        JetColor(0xFF5FC6C9),
      ]);
  final core.ChartLayout layout = core.layoutChart(
    chart,
    theme: t,
    size: core.ChartSize(bounds.width, bounds.height),
    measurer: ChartEngineMeasurer(measurer),
  );
  final ChartConversionGaps gaps = ChartConversionGaps();
  final List<FramePrimitive> out = <FramePrimitive>[];
  void walk(core.ChartPrimitive p) {
    switch (p) {
      case core.RectPrimitive():
        out.add(RectPrimitive(
          bounds: JetRect(
              x: bounds.x + p.rect.left,
              y: bounds.y + p.rect.top,
              width: p.rect.width,
              height: p.rect.height),
          fill: p.fill == null ? null : _color(p.fill!),
          stroke: p.stroke == null ? null : _color(p.stroke!),
          strokeWidth: p.strokeWidth,
          elementId: elementId,
        ));
      case core.PathPrimitive():
        if (p.points.isEmpty) return;
        if (p.dash != null) gaps.dashesDropped++;
        JetColor? fill = p.fill == null ? null : _color(p.fill!);
        if (fill != null && p.fillOpacity < 1) {
          gaps.opacityBlended++;
          fill = _blendOnWhite(fill, p.fillOpacity);
        }
        out.add(_polyline(
          p.points
              .map((core.ChartPoint q) =>
                  JetOffset(bounds.x + q.x, bounds.y + q.y))
              .toList(),
          closed: p.closed,
          fill: fill,
          stroke: p.stroke == null ? null : _color(p.stroke!),
          strokeWidth: p.strokeWidth,
          elementId: elementId,
        ));
      case core.ArcPrimitive():
        gaps.arcsFlattened++;
        out.add(_arc(p, bounds, elementId));
      case core.TextPrimitive():
        final JetTextStyle st = _jetStyle(p.style);
        final MeasuredText m = measurer.measure(p.text, st);
        out.add(TextRunPrimitive(
          bounds: JetRect(
              x: bounds.x + p.rect.left,
              y: bounds.y + p.rect.top,
              width: p.rect.width,
              height: p.rect.height),
          lines: m.lines,
          style: st,
          fontFamily: m.fontFamily,
          rotation: p.rotationDegrees * math.pi / 180,
          elementId: elementId,
        ));
      case core.ClipPrimitive():
        gaps.clipsDropped++;
        p.children.forEach(walk);
    }
  }

  layout.primitives.forEach(walk);
  return ChartFrameResult(out, gaps, layout);
}

JetColor _blendOnWhite(JetColor c, double opacity) {
  int ch(int v) => (v * opacity + 255 * (1 - opacity)).round().clamp(0, 255);
  return JetColor.fromARGB(255, ch((c.argb >> 16) & 0xFF),
      ch((c.argb >> 8) & 0xFF), ch(c.argb & 0xFF));
}

PathPrimitive _polyline(
  List<JetOffset> pts, {
  required bool closed,
  JetColor? fill,
  JetColor? stroke,
  required double strokeWidth,
  String? elementId,
}) {
  double minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
  for (final JetOffset p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  return PathPrimitive(
    bounds: JetRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
    commands: <PathCommand>[
      MoveTo(pts.first),
      for (final JetOffset p in pts.skip(1)) LineTo(p),
      if (closed) const ClosePath(),
    ],
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
    elementId: elementId,
  );
}

PathPrimitive _arc(core.ArcPrimitive a, JetRect bounds, String? elementId) {
  final double sweep = a.sweepAngle;
  // One vertex per 3 degrees at least, so a pie edge stays smooth in a PDF.
  final int steps = math.max(2, (sweep.abs() / 3).ceil());
  JetOffset at(double r, double deg) {
    final double rad = deg * math.pi / 180;
    return JetOffset(bounds.x + a.center.x + r * math.cos(rad),
        bounds.y + a.center.y + r * math.sin(rad));
  }

  final List<JetOffset> pts = <JetOffset>[];
  if (a.innerRadius <= 0) {
    pts.add(JetOffset(bounds.x + a.center.x, bounds.y + a.center.y));
  }
  for (int i = 0; i <= steps; i++) {
    pts.add(at(a.radius, a.startAngle + sweep * i / steps));
  }
  if (a.innerRadius > 0) {
    for (int i = steps; i >= 0; i--) {
      pts.add(at(a.innerRadius, a.startAngle + sweep * i / steps));
    }
  }
  return _polyline(
    pts,
    closed: true,
    fill: a.fill == null ? null : _color(a.fill!),
    stroke: a.stroke == null ? null : _color(a.stroke!),
    strokeWidth: a.strokeWidth,
    elementId: elementId,
  );
}
