// ReportFiller: the flat Fill data pass (007b).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect r = JetRect(x: 0, y: 0, width: 100, height: 10);

TextElement t(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: r, text: text ?? '', expression: expr);

ReportTemplate template({
  List<ReportElement> title = const <ReportElement>[],
  List<ReportElement> detail = const <ReportElement>[],
  List<ReportElement> summary = const <ReportElement>[],
  List<ReportElement> noData = const <ReportElement>[],
  List<ReportVariable> variables = const <ReportVariable>[],
  List<ReportGroup> groups = const <ReportGroup>[],
}) =>
    ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      variables: variables,
      groups: groups,
      bands: <ReportBand>[
        if (title.isNotEmpty) ReportBand(type: BandType.title, height: 10, elements: title),
        if (detail.isNotEmpty) ReportBand(type: BandType.detail, height: 10, elements: detail),
        if (summary.isNotEmpty) ReportBand(type: BandType.summary, height: 10, elements: summary),
        if (noData.isNotEmpty) ReportBand(type: BandType.noData, height: 10, elements: noData),
      ],
    );

void main() {
  test('flat data golden — title once, one detail per row, summary once', () {
    final FillResult res = ReportFiller().fill(
      template(
        title: <ReportElement>[t('h', text: 'Report')],
        detail: <ReportElement>[t('d', expr: r'$F{name}')],
        summary: <ReportElement>[t('s', text: 'End')],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'name': 'Ada'},
        <String, Object?>{'name': 'Bob'},
      ]),
    );
    final List<BandType> types =
        res.report.bands.map((b) => b.type).toList();
    expect(types, <BandType>[
      BandType.title,
      BandType.detail,
      BandType.detail,
      BandType.summary,
    ]);
    final String detail0 =
        (res.report.bands[1].elements.single as TextElement).text;
    final String detail1 =
        (res.report.bands[2].elements.single as TextElement).text;
    expect(<String>[detail0, detail1], <String>['Ada', 'Bob']);
  });

  test('running total in detail, grand total in summary', () {
    final FillResult res = ReportFiller().fill(
      template(
        detail: <ReportElement>[t('d', expr: r'$V{total}')],
        summary: <ReportElement>[t('s', expr: r'$V{total}')],
        variables: const <ReportVariable>[
          ReportVariable(
              name: 'total', expression: r'$F{amount}', calculation: JetCalculation.sum),
        ],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'amount': 10},
        <String, Object?>{'amount': 5},
      ]),
    );
    // detail bands are at indices 0 and 1; summary last.
    expect((res.report.bands[0].elements.single as TextElement).text, '10.0');
    expect((res.report.bands[1].elements.single as TextElement).text, '15.0');
    expect((res.report.bands.last.elements.single as TextElement).text, '15.0');
    // Each band freezes its OWN snapshot: band 0 captured 10 (after row 1),
    // band 1 captured 15 (after row 2). If variables were a live reference both
    // would read 15 — so pinning both rows guards the per-band-copy invariant.
    expect(res.report.bands[0].variables['total'], const JetNumber(10));
    expect(res.report.bands[1].variables['total'], const JetNumber(15));
  });

  test('empty source emits noData, no detail/summary', () {
    final FillResult res = ReportFiller().fill(
      template(
        detail: <ReportElement>[t('d', expr: r'$F{name}')],
        summary: <ReportElement>[t('s', text: 'End')],
        noData: <ReportElement>[t('n', text: 'No data')],
      ),
      JetInMemoryDataSource(const <Map<String, Object?>>[]),
    );
    expect(res.report.bands.map((b) => b.type).toList(),
        <BandType>[BandType.noData]);
  });

  test('summary has no row context — \$F{} blanks, \$V{} resolves', () {
    final FillResult res = ReportFiller().fill(
      template(
        summary: <ReportElement>[t('s', expr: r'$F{name}')],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'name': 'Ada'},
      ]),
    );
    expect((res.report.bands.last.elements.single as TextElement).text, '');
    // §5: $F{} with no row (summary) blanks SILENTLY — no warning/error.
    expect(res.diagnostics.entries, isEmpty);
  });

  test('undeclared field in a variable warns (schema-drift signal)', () {
    final FillResult res = ReportFiller().fill(
      template(
        detail: <ReportElement>[t('d', text: '.')],
        variables: const <ReportVariable>[
          ReportVariable(
              name: 'total', expression: r'$F{typo}', calculation: JetCalculation.sum),
        ],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'amount': 10},
      ]),
    );
    expect(
        res.diagnostics.entries
            .where((e) => e.severity == DiagnosticSeverity.warning)
            .length,
        greaterThanOrEqualTo(1));
  });

  test('page-scoped reference in a detail element is an error', () {
    final FillResult res = ReportFiller().fill(
      template(detail: <ReportElement>[t('d', text: 'fb', expr: r'$V{PAGE_NUMBER}')]),
      JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{'x': 1}]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect((res.report.bands[0].elements.single as TextElement).text, 'fb');
  });

  test('page-scoped reference in a variable expression is an error', () {
    final FillResult res = ReportFiller().fill(
      template(
        detail: <ReportElement>[t('d', text: '.')],
        variables: const <ReportVariable>[
          ReportVariable(name: 'v', expression: r'$V{PAGE_NUMBER}'),
        ],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{'x': 1}]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect(res.diagnostics.entries.any((e) => e.message.contains('variable "v"')),
        isTrue); // site-tagged
  });

  test('page-scoped reference in a group expression is an error', () {
    final FillResult res = ReportFiller().fill(
      template(
        detail: <ReportElement>[t('d', text: '.')],
        groups: const <ReportGroup>[
          ReportGroup(name: 'g', expression: r'$V{PAGE_NUMBER}'),
        ],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{'x': 1}]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect(res.diagnostics.entries.any((e) => e.message.contains('group "g"')),
        isTrue); // site-tagged
  });

  test('page-scoped reference in a noData element is an error', () {
    final FillResult res = ReportFiller().fill(
      template(noData: <ReportElement>[t('n', text: 'none', expr: r'$V{PAGE_NUMBER}')]),
      JetInMemoryDataSource(const <Map<String, Object?>>[]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect((res.report.bands.single.elements.single as TextElement).text, 'none');
  });

  test('a malformed variable expression fails fast (throws)', () {
    expect(
      () => ReportFiller().fill(
        template(
          detail: <ReportElement>[t('d', text: '.')],
          variables: const <ReportVariable>[
            ReportVariable(name: 'v', expression: r'CONCAT('),
          ],
        ),
        JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{'x': 1}]),
      ),
      throwsA(isA<ExpressionException>()),
    );
  });

  test('determinism — re-filling identical inputs yields an equal report', () {
    ReportTemplate make() => template(detail: <ReportElement>[t('d', expr: r'$F{n}')]);
    JetInMemoryDataSource src() =>
        JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{'n': 'a'}]);
    expect(ReportFiller().fill(make(), src()).report,
        ReportFiller().fill(make(), src()).report);
  });

  test('title has no row context — \$F{} blanks silently', () {
    final FillResult res = ReportFiller().fill(
      template(
        title: <ReportElement>[t('h', expr: r'$F{name}')],
        detail: <ReportElement>[t('d', text: '.')],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'name': 'Ada'},
      ]),
    );
    // title is the first band; $F{} with no row → blank, no diagnostic.
    expect((res.report.bands.first.elements.single as TextElement).text, '');
    expect(res.diagnostics.entries, isEmpty);
  });

  test('page-scoped reference in a title element is an error', () {
    final FillResult res = ReportFiller().fill(
      template(
        title: <ReportElement>[t('h', text: 'fb', expr: r'$V{PAGE_NUMBER}')],
        detail: <ReportElement>[t('d', text: '.')],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{'x': 1}]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    // authored text preserved (not blanked, not !ERR)
    expect((res.report.bands.first.elements.single as TextElement).text, 'fb');
  });

  test('page-scoped reference in a summary element is an error', () {
    final FillResult res = ReportFiller().fill(
      template(
        summary: <ReportElement>[t('s', text: 'fb', expr: r'$V{PAGE_NUMBER}')],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{'x': 1}]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect((res.report.bands.last.elements.single as TextElement).text, 'fb');
  });
}
