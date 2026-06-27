// test/domain/elements/chart_element_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  const bounds = JetRect(x: 0, y: 0, width: 200, height: 120);
  ChartElement make() => const ChartElement(
        id: 'c1',
        bounds: bounds,
        chartType: ChartType.bar,
        collectionField: 'months',
        categoryExpression: r'$F{label}',
        valueExpression: r'$F{revenue}',
        title: 'Revenue',
      );

  test('typeKey is chart', () => expect(make().typeKey, 'chart'));

  test('withBounds preserves every other field', () {
    final moved =
        make().withBounds(const JetRect(x: 5, y: 6, width: 50, height: 40));
    expect(moved.bounds, const JetRect(x: 5, y: 6, width: 50, height: 40));
    expect(moved.chartType, ChartType.bar);
    expect(moved.collectionField, 'months');
    expect(moved.categoryExpression, r'$F{label}');
    expect(moved.valueExpression, r'$F{revenue}');
    expect(moved.title, 'Revenue');
  });

  test('withName / withVisible preserve binding fields', () {
    final named = make().withName('Chart A');
    expect(named.name, 'Chart A');
    expect(named.collectionField, 'months');
    final vis = make().withVisible(const BoolProperty(expression: r'$F{show}'));
    expect(vis.collectionField, 'months');
    expect(vis.valueExpression, r'$F{revenue}');
  });

  test('copyWith replaces only named fields', () {
    final c = make().copyWith(chartType: ChartType.pie, showAxes: false);
    expect(c.chartType, ChartType.pie);
    expect(c.showAxes, false);
    expect(c.collectionField, 'months');
  });

  test('points default empty and carry through copyWith', () {
    expect(make().points, isEmpty);
    final withPts = make()
        .copyWith(points: const [ChartPoint('Jan', 10), ChartPoint('Feb', 20)]);
    expect(
        withPts.points, const [ChartPoint('Jan', 10), ChartPoint('Feb', 20)]);
  });

  test('equality is by value', () {
    expect(make(), equals(make()));
    expect(make().copyWith(title: 'Other'), isNot(equals(make())));
  });
}
