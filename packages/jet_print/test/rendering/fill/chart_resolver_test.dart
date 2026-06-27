// ChartElement fill resolution: bound collection → concrete series (Task 3).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';
import 'package:jet_print/src/rendering/fill/element_resolver.dart';

ElementResolver resolver() {
  final JetFunctionRegistry f = JetFunctionRegistry();
  registerBuiltInFunctions(f);
  return ElementResolver(functions: f, diagnostics: ReportDiagnostics());
}

ElementResolver resolverWith(ReportDiagnostics diags) {
  final JetFunctionRegistry f = JetFunctionRegistry();
  registerBuiltInFunctions(f);
  return ElementResolver(functions: f, diagnostics: diags);
}

DataRow rowWith(Object? months) => DataRow(
      fields: const <FieldDef>[FieldDef('months')],
      values: <String, Object?>{'months': months},
    );

const ChartElement chart = ChartElement(
  id: 'c1',
  bounds: JetRect(x: 0, y: 0, width: 200, height: 120),
  chartType: ChartType.bar,
  collectionField: 'months',
  categoryExpression: r'$F{label}',
  valueExpression: r'$F{revenue}',
);

void main() {
  test('resolves the bound collection into a series', () {
    final ChartElement r = resolver().resolve(chart,
        row: rowWith(<Object?>[
          <String, Object?>{'label': 'Jan', 'revenue': 10},
          <String, Object?>{'label': 'Feb', 'revenue': 25},
        ])) as ChartElement;
    expect(r.points,
        const <ChartPoint>[ChartPoint('Jan', 10), ChartPoint('Feb', 25)]);
    expect(r.collectionField, 'months'); // binding preserved
  });

  test('empty / missing collection → empty series, no throw', () {
    expect(
        (resolver().resolve(chart, row: rowWith(<Object?>[])) as ChartElement)
            .points,
        isEmpty);
    expect(
        (resolver().resolve(chart, row: rowWith(null)) as ChartElement).points,
        isEmpty);
  });

  test('non-numeric value resolves to 0 and warns', () {
    final ReportDiagnostics diags = ReportDiagnostics();
    final ChartElement r = resolverWith(diags).resolve(chart,
        row: rowWith(<Object?>[
          <String, Object?>{'label': 'Jan', 'revenue': 'oops'},
        ])) as ChartElement;
    expect(r.points.single.value, 0);
    expect(diags.entries, isNotEmpty);
  });

  test('null categoryExpression labels by index', () {
    const ChartElement noCat = ChartElement(
        id: 'c2',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        chartType: ChartType.pie,
        collectionField: 'months',
        valueExpression: r'$F{revenue}');
    final ChartElement r = resolver().resolve(noCat,
        row: rowWith(<Object?>[
          <String, Object?>{'revenue': 5},
          <String, Object?>{'revenue': 7},
        ])) as ChartElement;
    expect(
        r.points.map((ChartPoint p) => p.label).toList(), <String>['1', '2']);
  });
}
