/// Renders a [ChartElement]: jet_charts_core lays the chart out and
/// `chart_frame_converter.dart` spells the result in frame primitives, so
/// canvas, preview, and export agree by construction. With no data it draws a
/// chart-glyph placeholder instead.
library;

import 'package:jet_charts_core/jet_charts_core.dart' as core;

import '../../../domain/elements/chart_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/styles/color.dart';
import '../../../domain/styles/text_style.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../chart/chart_frame_converter.dart';
import '../chart/chart_model_mapper.dart';
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

/// The palette for pie slices (bar/line use the element's seriesColor).
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
    // No resolved series (design-time, unbound, or an empty collection): draw a
    // chart-glyph placeholder instead of a blank box (render-don't-crash), the
    // same affordance the source-less image element gives.
    if (el.points.isEmpty) {
      final double titleGutter = el.title != null ? kChartTitleGutter : 0;
      final bool axes = el.showAxes && el.chartType != ChartType.pie;
      final double plotLeft = bounds.x + (axes ? kChartGutterLeft : 0);
      final double plotTop = bounds.y + titleGutter;
      final double plotBottom = bounds.y +
          bounds.height -
          (axes ? kChartGutterBottom : 0) -
          (el.showLegend ? kChartLegendGutter : 0);
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
      emitChartPlaceholder(
          out,
          JetRect(
            x: plotLeft,
            y: plotTop,
            width: (bounds.x + bounds.width) - plotLeft,
            height: plotBottom - plotTop,
          ),
          el.chartType,
          elementId: el.id);
      return;
    }

    // Data present: jet_charts_core lays the chart out, with the engine's own
    // measurer, and the result is spelled in frame primitives — so the canvas,
    // preview, PNG and PDF all draw it through the one paint path.
    for (final FramePrimitive p in convertChartPrimitives(
      core
          .layoutChart(
            chartFor(el),
            theme: reportChartTheme(kChartPalette),
            size: core.ChartSize(bounds.width, bounds.height),
            measurer: ChartEngineMeasurer(ctx.measurer),
          )
          .primitives,
      bounds: bounds,
      measurer: ctx.measurer,
      elementId: el.id,
    )) {
      out.add(p);
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
