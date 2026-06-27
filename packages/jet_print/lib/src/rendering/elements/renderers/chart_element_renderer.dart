/// Renders a [ChartElement] by replaying pure [chart_geometry] into frame
/// primitives (rects/paths/lines/text) — no widget chart library, so canvas,
/// preview, and export agree by construction.
library;

import 'dart:math' as math;

import '../../../domain/elements/chart_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/styles/color.dart';
import '../../../domain/styles/text_style.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../chart/chart_geometry.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// Left gutter (points) reserved for the value-axis tick labels.
const double kChartGutterLeft = 28;

/// Bottom gutter (points) reserved for category labels.
const double kChartGutterBottom = 14;

/// Top gutter (points) reserved for the title (used only when a title is set).
const double kChartTitleGutter = 14;

/// Bottom gutter (points) reserved for the legend row.
const double kChartLegendGutter = 16;

/// Width and height of each legend color swatch.
const double kChartLegendSwatchSize = 8;

/// Horizontal gap between swatch and its label.
const double kChartLegendSwatchLabelGap = 3;

/// Horizontal gap between legend entries.
const double kChartLegendEntryGap = 12;

/// The slice palette for pie charts (bar/line use the element's seriesColor).
const List<JetColor> kChartPalette = <JetColor>[
  JetColor(0xFF4F8DF7),
  JetColor(0xFFF7894F),
  JetColor(0xFF4FB76B),
  JetColor(0xFFB74F9E),
  JetColor(0xFFE0C341),
  JetColor(0xFF5FC6C9),
];

/// The built-in renderer for `chart` elements.
class ChartElementRenderer extends ElementRenderer<ChartElement> {
  /// Const constructor.
  const ChartElementRenderer();

  static const JetTextStyle _labelStyle = JetTextStyle(fontSize: 7);

  @override
  JetSize measure(
          ChartElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(
      ChartElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    final double titleGutter = el.title != null ? kChartTitleGutter : 0;
    final double legendGutter = el.showLegend ? kChartLegendGutter : 0;
    final bool axes = el.showAxes && el.chartType != ChartType.pie;
    final double plotLeft = bounds.x + (axes ? kChartGutterLeft : 0);
    final double plotTop = bounds.y + titleGutter;
    final double plotBottom = bounds.y +
        bounds.height -
        (axes ? kChartGutterBottom : 0) -
        legendGutter;
    final JetRect plot = JetRect(
      x: plotLeft,
      y: plotTop,
      width: (bounds.x + bounds.width) - plotLeft,
      height: plotBottom - plotTop,
    );

    // Title
    if (el.title != null) {
      _text(
        ctx,
        out,
        el.title!,
        JetRect(
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: kChartTitleGutter),
        el.id,
      );
    }

    // No resolved series (design-time, unbound, or an empty collection): draw a
    // chart-glyph placeholder instead of a blank box (render-don't-crash), the
    // same affordance the source-less image element gives.
    if (el.points.isEmpty) {
      emitChartPlaceholder(out, plot, el.chartType, elementId: el.id);
      return;
    }

    switch (el.chartType) {
      case ChartType.bar:
        _emitCartesian(el, ctx, plot, out, bars: true);
      case ChartType.line:
        _emitCartesian(el, ctx, plot, out, bars: false);
      case ChartType.pie:
        _emitPie(el, ctx, plot, out);
    }

    // Legend (below the plot area)
    if (el.showLegend) {
      _emitLegend(el, ctx, bounds, plot, out);
    }
  }

  void _emitPie(
      ChartElement el, RenderContext ctx, JetRect plot, FrameBuilder out) {
    final List<PieSlice> slices = pieSlices(el.points, plot);
    final double total = el.points.fold<double>(
        0, (double s, ChartPoint p) => p.value > 0 ? s + p.value : s);

    for (final PieSlice s in slices) {
      out.add(PathPrimitive(
        bounds: plot,
        commands: s.commands,
        fill: kChartPalette[s.index % kChartPalette.length],
        elementId: el.id,
      ));

      // Percent label at mid-angle, 60% of radius from center.
      if (el.showValueLabels && total > 0) {
        final double midAngle = s.startAngle + s.sweepAngle / 2;
        final double cx = plot.x + plot.width / 2;
        final double cy = plot.y + plot.height / 2;
        final double r = math.min(plot.width, plot.height) / 2;
        const double labelRadius = 0.60;
        final double lx = cx + r * labelRadius * math.cos(midAngle);
        final double ly = cy + r * labelRadius * math.sin(midAngle);
        final int pct = ((s.value / total) * 100).round();
        const double hw = 14;
        const double hh = 8;
        _text(
          ctx,
          out,
          '$pct%',
          JetRect(x: lx - hw / 2, y: ly - hh / 2, width: hw, height: hh),
          el.id,
        );
      }
    }
  }

  /// Draws a horizontal legend row below the plot area.
  ///
  /// For pie charts one entry per slice (palette color + category label);
  /// for bar/line a single entry (series color + chart title or "Series").
  /// Entries that exceed the available width are silently clipped (v1).
  void _emitLegend(ChartElement el, RenderContext ctx, JetRect bounds,
      JetRect plot, FrameBuilder out) {
    final double legendY = bounds.y +
        bounds.height -
        kChartLegendGutter +
        (kChartLegendGutter - kChartLegendSwatchSize) / 2;

    final List<({JetColor color, String label})> entries;
    if (el.chartType == ChartType.pie) {
      final List<ChartPoint> pos = el.points.where((p) => p.value > 0).toList();
      entries = <({JetColor color, String label})>[
        for (var i = 0; i < pos.length; i++)
          (
            color: kChartPalette[i % kChartPalette.length],
            label: pos[i].label,
          ),
      ];
    } else {
      entries = <({JetColor color, String label})>[
        (color: el.seriesColor, label: el.title ?? 'Series'),
      ];
    }

    double x = bounds.x;
    for (final entry in entries) {
      if (x >= bounds.x + bounds.width) break; // clipped

      // Color swatch
      out.add(RectPrimitive(
        bounds: JetRect(
            x: x,
            y: legendY,
            width: kChartLegendSwatchSize,
            height: kChartLegendSwatchSize),
        fill: entry.color,
        elementId: el.id,
      ));
      x += kChartLegendSwatchSize + kChartLegendSwatchLabelGap;

      // Label
      const double labelW = 40;
      _text(
        ctx,
        out,
        entry.label,
        JetRect(
            x: x, y: legendY, width: labelW, height: kChartLegendSwatchSize),
        el.id,
      );
      x += labelW + kChartLegendEntryGap;
    }
  }

  void _emitCartesian(
    ChartElement el,
    RenderContext ctx,
    JetRect plot,
    FrameBuilder out, {
    required bool bars,
  }) {
    if (el.points.isEmpty) return;

    final double maxV = el.points
        .fold<double>(0, (double m, ChartPoint p) => p.value > m ? p.value : m);
    final AxisScale axis = niceAxis(maxV);

    // Axis gridlines + tick labels
    if (el.showAxes) {
      for (final double t in axis.ticks) {
        final double frac = t / axis.niceMax;
        final double y = plot.y + plot.height - frac * plot.height;
        out.add(LinePrimitive(
          bounds: plot,
          start: JetOffset(plot.x, y),
          end: JetOffset(plot.x + plot.width, y),
          color: const JetColor(0xFFDDDDDD),
          strokeWidth: 0.5,
          elementId: el.id,
        ));
        _text(
          ctx,
          out,
          t.toStringAsFixed(0),
          JetRect(
              x: plot.x - kChartGutterLeft,
              y: y - 4,
              width: kChartGutterLeft - 2,
              height: 8),
          el.id,
        );
      }
    }

    if (bars) {
      final List<JetRect> rects = barRects(el.points, plot, axis);
      for (var i = 0; i < rects.length; i++) {
        out.add(RectPrimitive(
            bounds: rects[i], fill: el.seriesColor, elementId: el.id));
        if (el.showValueLabels) {
          // Clamp label y so it doesn't clip above the plot top.
          const double labelH = 8;
          final double rawY = rects[i].y - labelH;
          final double labelY = rawY < plot.y
              ? rects[i].y
              : rawY; // draw inside bar when too close
          _text(
            ctx,
            out,
            el.points[i].value.toStringAsFixed(0),
            JetRect(
                x: rects[i].x,
                y: labelY,
                width: rects[i].width,
                height: labelH),
            el.id,
          );
        }
      }
    } else {
      final List<JetOffset> line = linePolyline(el.points, plot, axis);
      if (line.isNotEmpty) {
        out.add(PathPrimitive(
          bounds: plot,
          commands: <PathCommand>[
            MoveTo(line.first),
            for (final JetOffset p in line.skip(1)) LineTo(p),
          ],
          stroke: el.seriesColor,
          strokeWidth: 1.5,
          elementId: el.id,
        ));
      }
    }

    // Category labels along the bottom
    if (el.showAxes) {
      final double slot = plot.width / el.points.length;
      for (var i = 0; i < el.points.length; i++) {
        _text(
          ctx,
          out,
          el.points[i].label,
          JetRect(
              x: plot.x + i * slot,
              y: plot.y + plot.height + 2,
              width: slot,
              height: kChartGutterBottom - 2),
          el.id,
        );
      }
    }
  }

  void _text(
      RenderContext ctx, FrameBuilder out, String s, JetRect box, String id) {
    final measured = ctx.measurer.measure(s, _labelStyle, maxWidth: box.width);
    out.add(TextRunPrimitive(
      bounds: box,
      lines: measured.lines,
      style: _labelStyle,
      fontFamily: measured.fontFamily,
      elementId: id,
    ));
  }
}
