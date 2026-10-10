// What the README examples actually print, run by run. The example tests
// (test/example_*_test.dart) prove the examples compile, validate and fill
// without diagnostics; this proves the text the README promises: group
// headers, per-group subtotals, the grand total, page numbers, and the
// designer preview's greetings.
//
// White-box: frame primitives are not public, so reading painted text needs the
// two `src/` imports below (test/rendering/ is allowlisted for that). VM only,
// for the same reason as the example tests: see test/example_test.dart.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart'
    show frameOf;
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

import '../support/example_web.dart'
    if (dart.library.io) '../support/example_io.dart';

List<String> _texts(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p in frameOf(report.pageAt(i))
            .primitives
            .whereType<TextRunPrimitive>())
          p.lines.map((TextLine l) => l.text).join(),
    ];

void main() {
  test('the sales example prints groups, subtotals, total and page numbers',
      () {
    expect(_texts(renderSales(ordersFromJson)), <String>[
      'North',
      'Ada', '120.50', //
      'Grace', '80.00',
      '200.50', // North subtotal
      'South',
      'Linus', '42.25',
      '42.25', // South subtotal
      '242.75', // grand total
      'Page 1 of 1',
    ]);
  });

  test('the designer example previews a greeting per customer row', () {
    expect(
      _texts(const JetReportEngine()
          .renderDefinition(greetingsReport, customerRows)),
      <String>['Greetings', 'Hello, Ada!', 'Hello, Grace!'],
    );
  });
}
