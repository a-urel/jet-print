/// Maps the report model's [ChartElement] onto jet_charts_core's chart model,
/// so one layout engine serves the designer, preview, PNG and PDF.
library;

import 'package:jet_charts_core/jet_charts_core.dart' as core;

import '../../../domain/elements/chart_element.dart';

/// The core chart for [el]'s resolved [ChartElement.points].
///
/// Bar charts are vertical columns, as they have always been here. Pie data
/// labels are percentages, as before; cartesian ones are values.
core.Chart chartFor(ChartElement el) {
  final bool pie = el.chartType == ChartType.pie;
  final String? title = el.title;
  return core.Chart(
    kind: switch (el.chartType) {
      ChartType.bar => core.ChartKind.column,
      ChartType.line => core.ChartKind.line,
      ChartType.pie => core.ChartKind.pie,
    },
    title: title == null ? null : core.ChartTitle(text: title),
    series: <core.ChartSeries>[
      core.ChartSeries(
        name: core.ChartData<String>(values: <String>[title ?? 'Series']),
        categories: core.ChartData<Object>(
            values: <Object>[for (final ChartPoint p in el.points) p.label]),
        values: core.ChartData<double>(
            values: <double>[for (final ChartPoint p in el.points) p.value]),
        color: pie ? null : core.ChartColor.rgb(el.seriesColor.argb & 0xFFFFFF),
      ),
    ],
    categoryAxis: core.ChartAxis(visible: el.showAxes),
    valueAxis: core.ChartAxis(visible: el.showAxes, gridLines: true),
    legend: core.ChartLegend(visible: el.showLegend),
    dataLabels: core.ChartDataLabels(
      visible: el.showValueLabels,
      showValue: !pie,
      showPercent: pie,
    ),
  );
}
