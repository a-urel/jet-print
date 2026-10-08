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

  // Regression: an unrecognized chartType (one a newer build added) loaded as
  // bar and re-saved as "bar", silently replacing the author's choice.
  group('an unknown chartType survives a load/save round-trip', () {
    final Map<String, Object?> newer = <String, Object?>{
      'id': 'c9',
      'bounds': const JetRect(x: 0, y: 0, width: 100, height: 80).toJson(),
      'chartType': 'area',
      'collectionField': 'months',
      'valueExpression': r'$F{revenue}',
    };

    test('loads as bar for rendering, preserving the original name', () {
      final ChartElement loaded = codec.fromJson(newer);
      expect(loaded.chartType, ChartType.bar);
      expect(loaded.unknownChartType, 'area');
    });

    test('re-serializes byte-for-byte', () {
      expect(codec.toJson(codec.fromJson(newer)), equals(newer));
    });

    // Review finding on #65: copyWith kept the preserved name when the type
    // changed, so the codec re-wrote the old unknown type over the new one.
    test('copyWith(chartType:) supersedes the preserved name', () {
      final ChartElement picked =
          codec.fromJson(newer).copyWith(chartType: ChartType.pie);
      expect(picked.unknownChartType, isNull);
      expect(codec.toJson(picked)['chartType'], 'pie');
    });

    test('copyWith without chartType keeps the preserved name', () {
      final ChartElement edited =
          codec.fromJson(newer).copyWith(showAxes: false);
      expect(edited.unknownChartType, 'area');
      expect(codec.toJson(edited)['chartType'], 'area');
    });

    test('a known chartType never carries an unknown name', () {
      final ChartElement loaded =
          codec.fromJson(<String, Object?>{...newer, 'chartType': 'line'});
      expect(loaded.unknownChartType, isNull);
    });
  });
}
