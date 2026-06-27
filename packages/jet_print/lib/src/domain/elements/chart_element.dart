/// A chart element (spec 2026-06-27): a bar, line, or pie chart bound to a
/// collection field, resolved to a concrete [points] series at fill time and
/// drawn as frame primitives so canvas, preview, and export agree.
library;

import '../bool_property.dart';
import '../geometry.dart';
import '../report_element.dart';
import '../styles/color.dart';

/// The default series color for a new chart (a mid blue).
const JetColor kDefaultChartColor = JetColor(0xFF4F8DF7);

/// The form a [ChartElement] draws. Serializes by [name] — additive, so a chart
/// authored before a new type existed loads byte-for-byte unchanged.
enum ChartType {
  /// Vertical bars, one per series point, scaled to a nice-number value axis.
  bar,

  /// A polyline across the series points, scaled to a nice-number value axis.
  line,

  /// A pie: one wedge per point, angle proportional to its share of the total.
  pie,
}

/// One resolved series point: a [label] (category) and its numeric [value].
/// Produced at fill time from a [ChartElement]'s category/value expressions;
/// never serialized (a fill-time artifact, like a [TextElement]'s resolved text).
class ChartPoint {
  /// Creates a point.
  const ChartPoint(this.label, this.value);

  /// The category label (X axis / pie slice label).
  final String label;

  /// The numeric value (bar/line height, pie slice share).
  final double value;

  @override
  bool operator ==(Object other) =>
      other is ChartPoint && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => 'ChartPoint($label, $value)';
}

/// A chart bound to [collectionField], iterating it to build a series via
/// [categoryExpression] (label) and [valueExpression] (value).
///
/// [points] is empty in an authored element; the fill phase returns a resolved
/// copy with [points] filled and the binding fields left intact. The renderer
/// reads only [points] + the chrome flags.
class ChartElement extends ReportElement {
  /// Creates a chart element.
  const ChartElement({
    required super.id,
    required super.bounds,
    required this.chartType,
    required this.collectionField,
    required this.valueExpression,
    this.categoryExpression,
    this.title,
    this.showAxes = true,
    this.showValueLabels = false,
    this.showLegend = false,
    this.seriesColor = kDefaultChartColor,
    this.points = const <ChartPoint>[],
    super.name,
    super.visible,
  });

  /// The chart form (bar/line/pie).
  final ChartType chartType;

  /// The name of the bound collection field, resolved in the element's band scope.
  final String collectionField;

  /// Per-item value expression (e.g. `$F{revenue}`). Required.
  final String valueExpression;

  /// Per-item label expression (e.g. `$F{month}`). Null → the point index.
  final String? categoryExpression;

  /// Optional chart title drawn above the plot.
  final String? title;

  /// Draw the value axis (ticks + gridlines) and category labels (bar/line).
  final bool showAxes;

  /// Draw a value/percent label on each bar/slice.
  final bool showValueLabels;

  /// Draw a single-series legend swatch.
  final bool showLegend;

  /// The bar/line series color (pie derives a per-slice palette).
  final JetColor seriesColor;

  /// The resolved series. Empty until the fill phase fills it; never serialized.
  final List<ChartPoint> points;

  /// Returns a copy with the named fields replaced and the rest preserved.
  ChartElement copyWith({
    JetRect? bounds,
    ChartType? chartType,
    String? collectionField,
    String? valueExpression,
    String? categoryExpression,
    String? title,
    bool? showAxes,
    bool? showValueLabels,
    bool? showLegend,
    JetColor? seriesColor,
    List<ChartPoint>? points,
    String? name,
    BoolProperty? visible,
  }) =>
      ChartElement(
        id: id,
        bounds: bounds ?? this.bounds,
        chartType: chartType ?? this.chartType,
        collectionField: collectionField ?? this.collectionField,
        valueExpression: valueExpression ?? this.valueExpression,
        categoryExpression: categoryExpression ?? this.categoryExpression,
        title: title ?? this.title,
        showAxes: showAxes ?? this.showAxes,
        showValueLabels: showValueLabels ?? this.showValueLabels,
        showLegend: showLegend ?? this.showLegend,
        seriesColor: seriesColor ?? this.seriesColor,
        points: points ?? this.points,
        name: name ?? this.name,
        visible: visible ?? this.visible,
      );

  @override
  String get typeKey => 'chart';

  @override
  ChartElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  ChartElement withName(String? name) => ChartElement(
        id: id,
        bounds: bounds,
        chartType: chartType,
        collectionField: collectionField,
        valueExpression: valueExpression,
        categoryExpression: categoryExpression,
        title: title,
        showAxes: showAxes,
        showValueLabels: showValueLabels,
        showLegend: showLegend,
        seriesColor: seriesColor,
        points: points,
        name: name,
        visible: visible,
      );

  @override
  ChartElement withVisible(BoolProperty visible) => copyWith(visible: visible);

  @override
  bool operator ==(Object other) =>
      other is ChartElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.chartType == chartType &&
      other.collectionField == collectionField &&
      other.valueExpression == valueExpression &&
      other.categoryExpression == categoryExpression &&
      other.title == title &&
      other.showAxes == showAxes &&
      other.showValueLabels == showValueLabels &&
      other.showLegend == showLegend &&
      other.seriesColor == seriesColor &&
      _pointsEqual(other.points, points) &&
      other.name == name &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(
        id,
        bounds,
        chartType,
        collectionField,
        valueExpression,
        categoryExpression,
        title,
        showAxes,
        showValueLabels,
        showLegend,
        seriesColor,
        Object.hashAll(points),
        name,
        visible,
      );

  @override
  String toString() => 'ChartElement($id, ${chartType.name}, $collectionField)';
}

bool _pointsEqual(List<ChartPoint> a, List<ChartPoint> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
