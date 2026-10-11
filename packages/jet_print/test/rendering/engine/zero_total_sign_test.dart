// A column that should foot to zero prints `0,00`, not `-0,00` (#95).
//
// Amounts are doubles, so 0.3 - 0.1 - 0.2 sums to about -2.8e-17, and intl
// prints any value below zero with its sign. A value whose magnitude formats
// as zero now prints as zero.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart'
    show frameOf;
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;

const ReportDefinition _ledger = ReportDefinition(
  name: 'ledger',
  page: PageFormat.a4Portrait,
  body: ReportBody(
    summary: Band(
      id: 'summary',
      type: BandType.summary,
      height: 20,
      elements: <ReportElement>[
        TextElement(
          id: 'balance',
          bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
          text: 'balance',
          expression: r'SUM($F{amount})',
          format: '#,##0.00',
        ),
      ],
    ),
    root: DetailScope(id: 'root'),
  ),
);

void main() {
  test('the amounts really do drift below zero', () {
    expect(0.3 + -0.1 + -0.2, lessThan(0));
  });

  test('a balance that should foot to zero prints 0,00', () {
    final RenderedReport report = const JetReportEngine().renderDefinition(
      _ledger,
      JetInMemoryDataSource(const <Map<String, Object?>>[
        <String, Object?>{'amount': 0.3},
        <String, Object?>{'amount': -0.1},
        <String, Object?>{'amount': -0.2},
      ]),
      options: const RenderOptions(locale: Locale('tr')),
    );
    final List<String> printed = <String>[
      for (final FramePrimitive p in frameOf(report.pageAt(0)).primitives)
        if (p is TextRunPrimitive && p.elementId == 'balance')
          p.lines.map((TextLine l) => l.text).join(),
    ];
    expect(printed, <String>['0,00']);
  });
}
