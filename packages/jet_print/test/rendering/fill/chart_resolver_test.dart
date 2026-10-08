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

  // Regression (#63): an infinite value went straight into the series, and the
  // value axis threw on it (`Infinity.floor()`) — out of `pageAt`.
  for (final double bad in <double>[double.infinity, double.negativeInfinity]) {
    test('a non-finite value ($bad) resolves to 0 and warns', () {
      final ReportDiagnostics diags = ReportDiagnostics();
      final ChartElement r = resolverWith(diags).resolve(chart,
          row: rowWith(<Object?>[
            <String, Object?>{'label': 'Jan', 'revenue': bad},
            <String, Object?>{'label': 'Feb', 'revenue': 5},
          ])) as ChartElement;
      expect(r.points.map((ChartPoint p) => p.value).toList(), <double>[0, 5]);
      expect(diags.entries.where((Diagnostic d) => d.elementId == 'c1'),
          hasLength(1));
    });
  }

  test('a chart over an infinite value renders its page without throwing', () {
    const ReportDefinition def = ReportDefinition(
      name: 'Infinite chart',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
            id: 'detail',
            type: BandType.detail,
            height: 140,
            elements: <ReportElement>[chart],
          )),
        ]),
      ),
    );
    final RenderedReport report = const JetReportEngine().renderDefinition(
      def,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'months': <Map<String, Object?>>[
            <String, Object?>{'label': 'Jan', 'revenue': double.infinity},
          ],
        },
      ], fields: const <FieldDef>[
        FieldDef('months', type: JetFieldType.collection, fields: <FieldDef>[
          FieldDef('label', type: JetFieldType.string),
          FieldDef('revenue', type: JetFieldType.double),
        ]),
      ]),
    );
    expect(() => report.pageAt(0), returnsNormally);
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
