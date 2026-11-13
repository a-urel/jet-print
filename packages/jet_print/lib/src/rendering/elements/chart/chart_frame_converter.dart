/// JP0 spike: converts a jet_charts_core layout into frame primitives, so the
/// canvas, preview, PNG and PDF keep drawing one recorded picture.
///
/// Not wired into any renderer yet. Dashes, clips, fill opacity and arcs are
/// carried by the frame itself (`dashPattern`, `clip`, colour alpha, `ArcTo`).
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

JetColor _color(core.ChartColor c, {double opacity = 1}) =>
    JetColor(((opacity * 255).round().clamp(0, 255) << 24) | c.rgb);

/// The frame primitives of one chart.
class ChartFrameResult {
  /// Creates a result.
  const ChartFrameResult(this.primitives, this.layout);

  /// In paint order, in page coordinates.
  final List<FramePrimitive> primitives;

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
  return ChartFrameResult(
      convertChartPrimitives(layout.primitives,
          bounds: bounds, measurer: measurer, elementId: elementId),
      layout);
}

/// Converts core [primitives] (chart-local coordinates) into frame primitives
/// placed at [bounds]. Separate from [chartToFrame] so the mapping can be
/// pinned on hand-built primitives, not only on whatever a layout emits.
List<FramePrimitive> convertChartPrimitives(
  List<core.ChartPrimitive> primitives, {
  required JetRect bounds,
  required TextMeasurer measurer,
  String? elementId,
}) {
  final List<FramePrimitive> out = <FramePrimitive>[];
  JetRect page(core.ChartRect r) => JetRect(
      x: bounds.x + r.left,
      y: bounds.y + r.top,
      width: r.width,
      height: r.height);
  JetOffset at(core.ChartPoint q) => JetOffset(bounds.x + q.x, bounds.y + q.y);

  void walk(core.ChartPrimitive p, JetRect? clip) {
    switch (p) {
      case core.RectPrimitive():
        out.add(RectPrimitive(
          bounds: page(p.rect),
          fill: p.fill == null ? null : _color(p.fill!),
          stroke: p.stroke == null ? null : _color(p.stroke!),
          strokeWidth: p.strokeWidth,
          elementId: elementId,
          clip: clip,
        ));
      case core.PathPrimitive():
        if (p.points.isEmpty) return;
        final List<JetOffset> pts = p.points.map(at).toList();
        out.add(PathPrimitive(
          bounds: _boundsOf(pts),
          commands: <PathCommand>[
            MoveTo(pts.first),
            for (final JetOffset q in pts.skip(1)) LineTo(q),
            if (p.closed) const ClosePath(),
          ],
          fill: p.fill == null ? null : _color(p.fill!, opacity: p.fillOpacity),
          stroke: p.stroke == null ? null : _color(p.stroke!),
          strokeWidth: p.strokeWidth,
          dashPattern: p.dash,
          elementId: elementId,
          clip: clip,
        ));
      case core.ArcPrimitive():
        out.add(_arc(p, at(p.center), elementId, clip));
      case core.TextPrimitive():
        final JetTextStyle st = _jetStyle(p.style);
        final MeasuredText m = measurer.measure(p.text, st);
        out.add(TextRunPrimitive(
          bounds: page(p.rect),
          lines: m.lines,
          style: st,
          fontFamily: m.fontFamily,
          rotation: p.rotationDegrees * math.pi / 180,
          elementId: elementId,
          clip: clip,
        ));
      case core.ClipPrimitive():
        // Nested clips intersect in core's model; the converter has only the
        // innermost, which core never nests (see ChartLayout docs).
        for (final core.ChartPrimitive c in p.children) {
          walk(c, page(p.rect));
        }
    }
  }

  for (final core.ChartPrimitive p in primitives) {
    walk(p, null);
  }
  return out;
}

JetRect _boundsOf(List<JetOffset> pts) {
  double minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
  for (final JetOffset p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  return JetRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY);
}

/// A pie slice or donut segment as real arcs: centre -> outer arc -> close, or
/// outer arc -> inner arc back -> close for a ring. Core's angles are degrees.
PathPrimitive _arc(
    core.ArcPrimitive a, JetOffset c, String? elementId, JetRect? clip) {
  double rad(double deg) => deg * math.pi / 180;
  final double start = rad(a.startAngle);
  final double sweep = rad(a.sweepAngle);
  JetOffset on(double r, double t) =>
      JetOffset(c.dx + r * math.cos(t), c.dy + r * math.sin(t));
  final List<PathCommand> cmds = a.innerRadius > 0
      ? <PathCommand>[
          MoveTo(on(a.radius, start)),
          ArcTo(c, a.radius, start, sweep),
          LineTo(on(a.innerRadius, start + sweep)),
          ArcTo(c, a.innerRadius, start + sweep, -sweep),
          const ClosePath(),
        ]
      : sweep.abs() >= 2 * math.pi - 1e-9
          // A whole disc (a point marker): start on the rim. Starting at the
          // centre would leave a radial spoke when the path closes.
          ? <PathCommand>[
              MoveTo(on(a.radius, start)),
              ArcTo(c, a.radius, start, sweep),
              const ClosePath(),
            ]
          : <PathCommand>[
              MoveTo(c),
              ArcTo(c, a.radius, start, sweep),
              const ClosePath(),
            ];
  return PathPrimitive(
    // The full circle's square: a safe over-estimate of the slice.
    bounds: JetRect(
        x: c.dx - a.radius,
        y: c.dy - a.radius,
        width: a.radius * 2,
        height: a.radius * 2),
    commands: cmds,
    fill: a.fill == null ? null : _color(a.fill!),
    stroke: a.stroke == null ? null : _color(a.stroke!),
    strokeWidth: a.strokeWidth,
    elementId: elementId,
    clip: clip,
  );
}
