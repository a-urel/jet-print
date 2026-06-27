/// Edits a [ChartElement]'s properties in one undoable step, preserving every
/// field not named. A no-op for a non-chart or absent [id].
library;

import '../../../domain/elements/chart_element.dart';
import '../../../domain/report_element.dart';
import '../../../domain/styles/color.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the named chart properties on element [id].
///
/// Every field not mentioned is preserved via [ChartElement.copyWith] — the
/// silent-drop trap cannot occur here because the command only merges the
/// explicitly-supplied non-null overrides into the existing element.
///
/// A no-op for a non-chart or absent [id].
class SetChartOptionsCommand extends EditCommand {
  /// Creates a chart-options edit. Every parameter except [id] is optional;
  /// pass only the fields that should change.
  const SetChartOptionsCommand({
    required this.id,
    this.chartType,
    this.collectionField,
    this.valueExpression,
    this.categoryExpression,
    this.title,
    this.showAxes,
    this.showValueLabels,
    this.showLegend,
    this.seriesColor,
  });

  /// The target chart element.
  final String id;

  /// The chart form (null = leave unchanged).
  final ChartType? chartType;

  /// The bound collection field name (null = leave unchanged).
  final String? collectionField;

  /// Per-item value expression (null = leave unchanged).
  final String? valueExpression;

  /// Per-item category expression (null = leave unchanged).
  final String? categoryExpression;

  /// Optional chart title (null = leave unchanged).
  final String? title;

  /// Whether to draw the value axis (null = leave unchanged).
  final bool? showAxes;

  /// Whether to draw value labels on each bar/slice (null = leave unchanged).
  final bool? showValueLabels;

  /// Whether to draw a legend swatch (null = leave unchanged).
  final bool? showLegend;

  /// Series color (null = leave unchanged).
  final JetColor? seriesColor;

  @override
  String get label => 'Edit chart';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
          before.definition,
          id,
          (ReportElement e) => e is ChartElement
              ? e.copyWith(
                  chartType: chartType,
                  collectionField: collectionField,
                  valueExpression: valueExpression,
                  categoryExpression: categoryExpression,
                  title: title,
                  showAxes: showAxes,
                  showValueLabels: showValueLabels,
                  showLegend: showLegend,
                  seriesColor: seriesColor,
                )
              : e,
        ),
      );
}
