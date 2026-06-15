library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/aggregate_functions.dart';
import 'package:jet_print/src/expression/expression.dart';

void main() {
  test('maps the five aggregate names (case-insensitive) to calculations', () {
    expect(aggregateCalculationFor('SUM'), JetCalculation.sum);
    expect(aggregateCalculationFor('avg'), JetCalculation.average);
    expect(aggregateCalculationFor('Count'), JetCalculation.count);
    expect(aggregateCalculationFor('MIN'), JetCalculation.min);
    expect(aggregateCalculationFor('max'), JetCalculation.max);
    expect(aggregateCalculationFor('UPPER'), isNull);
  });

  test('detects a single-arg top-level aggregate call', () {
    final agg = topLevelAggregate(Expression.parse(r'SUM($F{x})').root);
    expect(agg, isNotNull);
    expect(agg!.calculation, JetCalculation.sum);
  });

  test('a multi-arg MIN/MAX is NOT an aggregate (scalar function)', () {
    expect(
        topLevelAggregate(Expression.parse(r'MIN($F{a}, $F{b})').root), isNull);
  });

  test('a non-top-level aggregate (nested in arithmetic) is not detected', () {
    expect(topLevelAggregate(Expression.parse(r'SUM($F{x}) + 1').root), isNull);
  });

  test('aggregateNameFor inverts the table and returns null off-table', () {
    expect(aggregateNameFor(JetCalculation.sum), 'SUM');
    expect(aggregateNameFor(JetCalculation.average), 'AVG');
    expect(aggregateNameFor(JetCalculation.count), 'COUNT');
    expect(aggregateNameFor(JetCalculation.min), 'MIN');
    expect(aggregateNameFor(JetCalculation.max), 'MAX');
    expect(aggregateNameFor(JetCalculation.none), isNull);
    expect(aggregateNameFor(JetCalculation.first), isNull);
  });
}
