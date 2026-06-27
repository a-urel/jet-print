// test/domain/serialization/chart_element_codec_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/domain/serialization/chart_element_codec.dart';

void main() {
  const codec = ChartElementCodec();

  test('round-trips every authored field', () {
    const el = ChartElement(
        id: 'c1',
        bounds: JetRect(x: 1, y: 2, width: 200, height: 120),
        chartType: ChartType.pie,
        collectionField: 'months',
        categoryExpression: r'$F{label}',
        valueExpression: r'$F{revenue}',
        title: 'Revenue',
        showAxes: false,
        showValueLabels: true,
        showLegend: true,
        seriesColor: JetColor(0xFF112233),
        name: 'Chart A');
    final back = codec.fromJson(codec.toJson(el));
    expect(back, equals(el));
  });

  test('omit-when-default keeps the JSON minimal', () {
    const el = ChartElement(
        id: 'c2',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        chartType: ChartType.bar,
        collectionField: 'm',
        valueExpression: r'$F{v}');
    final json = codec.toJson(el);
    expect(json.containsKey('title'), isFalse);
    expect(json.containsKey('categoryExpression'), isFalse);
    expect(json.containsKey('showAxes'), isFalse); // default true
    expect(json.containsKey('showValueLabels'), isFalse); // default false
    expect(json['type'] ?? json['chartType'], 'bar'); // serialize-by-name
  });

  test('points are never serialized (fill-time artifact)', () {
    const el = ChartElement(
        id: 'c3',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        chartType: ChartType.bar,
        collectionField: 'm',
        valueExpression: r'$F{v}',
        points: <ChartPoint>[ChartPoint('Jan', 1)]);
    expect(codec.toJson(el).containsKey('points'), isFalse);
  });
}
