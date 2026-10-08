/// A chart element: a bar, line, or pie chart bound to a
/// collection field, resolved to a concrete [points] series at fill time and
/// drawn as frame primitives so canvas, preview, and export agree.
library;

import '../bool_property.dart';
import '../copy_support.dart';
import '../geometry.dart';
import '../report_element.dart';
import '../styles/color.dart';
import '../value_equality.dart';

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
class ChartPoint with ValueEquality {
  /// Creates a point.
  const ChartPoint(this.label, this.value);

  /// The category label (X axis / pie slice label).
  final String label;

  /// The numeric value (bar/line height, pie slice share).
  final double value;

  @override
  List<Object?> get props => <Object?>[label, value];

  @override
  String toString() => 'ChartPoint($label, $value)';
}

/// A chart bound to [collectionField], iterating it to build a series via
/// [categoryExpression] (label) and [valueExpression] (value).
///
/// [points] is empty in an authored element; the fill phase returns a resolved
/// copy with [points] filled and the binding fields left intact. The renderer
/// reads only [points] + the chrome flags.
///
/// When a report serialized by a *newer* version names a [chartType] this
/// version does not recognize, the codec loads it as [ChartType.bar] (a safe
/// render default) while preserving the original name in [unknownChartType], so
/// re-saving does not discard it. A deliberate type pick clears it — the same
/// contract as `ShapeElement.unknownForm`.
class ChartElement extends ReportElement with ValueEquality {
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
    this.unknownChartType,
    super.name,
    super.visible,
  });

  /// The chart form (bar/line/pie).
  final ChartType chartType;

  /// The original serialized type name when [chartType] was unrecognized on
  /// load, else null. Non-null only when [chartType] is [ChartType.bar] (the
  /// safe render default for an unknown type); a deliberate pick clears it.
  final String? unknownChartType;

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
  ///
  /// The nullable fields — [categoryExpression], [title], [unknownChartType]
  /// and [name] — take a thunk: omit to preserve, pass `() => value` to
  /// replace (`() => null` clears).
  ///
  /// Supplying [chartType] is a type change, so it also drops a preserved
  /// [unknownChartType] — otherwise the codec would write the old unknown name
  /// over the new type — unless [unknownChartType] is passed explicitly.
  ChartElement copyWith({
    JetRect? bounds,
    ChartType? chartType,
    String? collectionField,
    String? valueExpression,
    String? Function()? categoryExpression,
    String? Function()? title,
    bool? showAxes,
    bool? showValueLabels,
    bool? showLegend,
    JetColor? seriesColor,
    List<ChartPoint>? points,
    String? Function()? unknownChartType,
    String? Function()? name,
    BoolProperty? visible,
  }) =>
      ChartElement(
        id: id,
        bounds: bounds ?? this.bounds,
        chartType: chartType ?? this.chartType,
        collectionField: collectionField ?? this.collectionField,
        valueExpression: valueExpression ?? this.valueExpression,
        categoryExpression: pick(categoryExpression, this.categoryExpression),
        title: pick(title, this.title),
        showAxes: showAxes ?? this.showAxes,
        showValueLabels: showValueLabels ?? this.showValueLabels,
        showLegend: showLegend ?? this.showLegend,
        seriesColor: seriesColor ?? this.seriesColor,
        points: points ?? this.points,
        unknownChartType: pick(
            unknownChartType, chartType == null ? this.unknownChartType : null),
        name: pick(name, this.name),
        visible: visible ?? this.visible,
      );

  @override
  String get typeKey => 'chart';

  @override
  ChartElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  ChartElement withName(String? name) => copyWith(name: () => name);

  @override
  ChartElement withVisible(BoolProperty visible) => copyWith(visible: visible);

  @override
  List<Object?> get props => <Object?>[
        ...baseProps,
        chartType,
        collectionField,
        valueExpression,
        categoryExpression,
        title,
        showAxes,
        showValueLabels,
        showLegend,
        seriesColor,
        points,
        unknownChartType,
      ];

  @override
  String toString() => 'ChartElement($id, ${chartType.name}, $collectionField)';
}
