// example/data_example.dart is the README's "Bind your data" code: JSON and
// object sources, a group per region with subtotals, a grand total and page
// numbers. See example_test.dart for why the import is conditional.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/example_web.dart'
    if (dart.library.io) 'support/example_io.dart';

void main() {
  test('the grouped report is valid against its schema', () {
    expect(validate(salesByRegion, schema: salesSchema), isEmpty);
  });

  test('the JSON source fills cleanly', () {
    final RenderedReport report = renderSales(ordersFromJson);
    expect(report.pageCount, 1);
    report.pageAt(0); // pages fill lazily; diagnostics arrive with the page
    expect(report.diagnostics.entries, isEmpty);
  });

  test('JSON rows and Dart objects print the same report', () {
    final RenderedReport fromJson = renderSales(ordersFromJson);
    final RenderedReport fromObjects = renderSales(ordersFromObjects);
    expect(fromObjects.pageCount, fromJson.pageCount);
    expect(fromObjects.pageAt(0).frame, fromJson.pageAt(0).frame);
    expect(fromObjects.diagnostics.entries, isEmpty);
  });
}
