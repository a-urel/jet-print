// ChartElement (report model) -> jet_charts_core Chart.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart' as core;
import 'package:jet_print/src/domain/elements/chart_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/chart/chart_model_mapper.dart';

ChartElement _el(
  ChartType t, {
  String? title,
  bool axes = true,
  bool labels = false,
  bool legend = false,
  JetColor color = kDefaultChartColor,
}) =>
    ChartElement(
      id: 'c',
      bounds: const JetRect(x: 0, y: 0, width: 100, height: 100),
      chartType: t,
      collectionField: 'm',
      valueExpression: r'$F{v}',
      title: title,
      showAxes: axes,
      showValueLabels: labels,
      showLegend: legend,
      seriesColor: color,
      points: const <ChartPoint>[ChartPoint('Jan', 10), ChartPoint('Feb', 20)],
    );

void main() {
  test('bar maps to column, line to line, pie to pie', () {
    expect(chartFor(_el(ChartType.bar)).kind, core.ChartKind.column);
    expect(chartFor(_el(ChartType.line)).kind, core.ChartKind.line);
    expect(chartFor(_el(ChartType.pie)).kind, core.ChartKind.pie);
  });

  test('points become one series of categories and values', () {
    final core.ChartSeries s = chartFor(_el(ChartType.bar)).series.single;
    expect(s.categories.values, <Object?>['Jan', 'Feb']);
    expect(s.values.values, <double?>[10, 20]);
  });

  test('series colour comes from the element; title names the series', () {
    final core.Chart c = chartFor(
        _el(ChartType.bar, title: 'Sales', color: const JetColor(0xFF112233)));
    expect(c.series.single.color!.rgb, 0x112233);
    expect(c.series.single.name.values.single, 'Sales');
    expect(c.title!.text, 'Sales');
  });

  test('no title: no chart title, series falls back to "Series"', () {
    final core.Chart c = chartFor(_el(ChartType.bar));
    expect(c.title, isNull);
    expect(c.series.single.name.values.single, 'Series');
  });

  test('showAxes drives both axes; gridlines follow the value axis', () {
    final core.Chart on = chartFor(_el(ChartType.bar));
    expect(on.categoryAxis.visible, isTrue);
    expect(on.valueAxis.visible, isTrue);
    expect(on.valueAxis.gridLines, isTrue);
    final core.Chart off = chartFor(_el(ChartType.bar, axes: false));
    expect(off.categoryAxis.visible, isFalse);
    expect(off.valueAxis.visible, isFalse);
  });

  test('legend and value labels follow the flags; pie labels are percents', () {
    expect(chartFor(_el(ChartType.bar)).legend.visible, isFalse);
    expect(chartFor(_el(ChartType.bar, legend: true)).legend.visible, isTrue);
    final core.ChartDataLabels bar =
        chartFor(_el(ChartType.bar, labels: true)).dataLabels;
    expect(bar.visible, isTrue);
    expect(bar.showValue, isTrue);
    final core.ChartDataLabels pie =
        chartFor(_el(ChartType.pie, labels: true)).dataLabels;
    expect(pie.showPercent, isTrue);
    expect(pie.showValue, isFalse);
  });
}
