/// JSON codec for [ChartElement]. Serialize-by-name, omit-when-default; the
/// fill-time [ChartElement.points] are never persisted.
library;

import '../bool_property.dart';
import '../elements/chart_element.dart';
import '../geometry.dart';
import '../styles/color.dart';
import 'element_codec.dart';

/// Serializes [ChartElement] to/from its field map.
class ChartElementCodec extends ElementCodec<ChartElement> {
  /// Const constructor (stateless).
  const ChartElementCodec();

  @override
  ChartElement fromJson(Map<String, Object?> json) {
    // Tolerant parse: an unrecognized chartType (e.g. one a newer version added)
    // loads as ChartType.bar — a safe render default.
    final String rawType = json['chartType'] as String? ?? 'bar';
    final ChartType type =
        ChartType.values.asNameMap()[rawType] ?? ChartType.bar;
    return ChartElement(
      id: json['id']! as String,
      bounds:
          JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
      chartType: type,
      collectionField: json['collectionField'] as String? ?? '',
      valueExpression: json['valueExpression'] as String? ?? '',
      categoryExpression: json['categoryExpression'] as String?,
      title: json['title'] as String?,
      showAxes: (json['showAxes'] as bool?) ?? true,
      showValueLabels: (json['showValueLabels'] as bool?) ?? false,
      showLegend: (json['showLegend'] as bool?) ?? false,
      seriesColor: json['seriesColor'] is String
          ? JetColor.fromJson(json['seriesColor']! as String)
          : kDefaultChartColor,
      name: json['name'] as String?,
      visible: json['visible'] is Map
          ? BoolProperty.fromJson(
              (json['visible']! as Map).cast<String, Object?>())
          : const BoolProperty(),
    );
  }

  @override
  Map<String, Object?> toJson(ChartElement el) => <String, Object?>{
        'id': el.id,
        'bounds': el.bounds.toJson(),
        'chartType': el.chartType.name,
        'collectionField': el.collectionField,
        'valueExpression': el.valueExpression,
        if (el.categoryExpression != null)
          'categoryExpression': el.categoryExpression,
        if (el.title != null) 'title': el.title,
        if (!el.showAxes) 'showAxes': false,
        if (el.showValueLabels) 'showValueLabels': true,
        if (el.showLegend) 'showLegend': true,
        if (el.seriesColor != kDefaultChartColor)
          'seriesColor': el.seriesColor.toJson(),
        if (el.name != null) 'name': el.name,
        if (el.visible != const BoolProperty()) 'visible': el.visible.toJson(),
      };
}
