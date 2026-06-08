// ReportFiller: the Fill data pass — flat bands (007b) + grouping (007c).
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
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect r = JetRect(x: 0, y: 0, width: 100, height: 10);

TextElement t(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: r, text: text ?? '', expression: expr);

ReportBand gh(String group, {String? text, String? expr}) => ReportBand(
      type: BandType.groupHeader,
      height: 10,
      group: group,
      elements: <ReportElement>[t('h-$group', text: text, expr: expr)],
    );
ReportBand gf(String group, {String? text, String? expr}) => ReportBand(
      type: BandType.groupFooter,
      height: 10,
      group: group,
      elements: <ReportElement>[t('f-$group', text: text, expr: expr)],
    );

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

  test('single group: header/detail/footer sequence with pre-reset subtotal', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      variables: const <ReportVariable>[
        ReportVariable(
            name: 'regionTotal',
            expression: r'$F{amt}',
            calculation: JetCalculation.sum,
            resetScope: VariableResetScope.group,
            resetGroup: 'region'),
      ],
      bands: <ReportBand>[
        gh('region', expr: r'$F{region}'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', expr: r'$V{regionTotal}')]),
        gf('region', expr: r'$V{regionTotal}'),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West', 'amt': 10},
        <String, Object?>{'region': 'West', 'amt': 5},
        <String, Object?>{'region': 'East', 'amt': 7},
      ]),
    );
    expect(res.report.bands.map((b) => b.type).toList(), <BandType>[
      BandType.groupHeader,
      BandType.detail,
      BandType.detail,
      BandType.groupFooter,
      BandType.groupHeader,
      BandType.detail,
      BandType.groupFooter,
    ]);
    String txt(int i) =>
        (res.report.bands[i].elements.single as TextElement).text;
    expect(txt(0), 'West'); // header shows the group key (first row)
    expect(txt(3), '15.0'); // CRUX: West footer = pre-reset subtotal, not 7
    expect(txt(4), 'East');
    expect(txt(6), '7.0'); // East footer (end of data)
  });

  test('header resolves the first row, footer the last row', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        gh('region', expr: r'$F{city}'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
        gf('region', expr: r'$F{city}'),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West', 'city': 'A'},
        <String, Object?>{'region': 'West', 'city': 'B'},
      ]),
    );
    expect((res.report.bands.first.elements.single as TextElement).text, 'A');
    expect((res.report.bands.last.elements.single as TextElement).text, 'B');
  });

  test('nested groups: header outer->inner, footer inner->outer, cascade', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
        ReportGroup(name: 'city', expression: r'$F{city}'),
      ],
      variables: const <ReportVariable>[
        ReportVariable(
            name: 'regionTotal',
            expression: r'$F{amt}',
            calculation: JetCalculation.sum,
            resetScope: VariableResetScope.group,
            resetGroup: 'region'),
        ReportVariable(
            name: 'cityTotal',
            expression: r'$F{amt}',
            calculation: JetCalculation.sum,
            resetScope: VariableResetScope.group,
            resetGroup: 'city'),
      ],
      bands: <ReportBand>[
        gh('region', expr: r'$F{region}'),
        gh('city', expr: r'$F{city}'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
        gf('city', expr: r'$V{cityTotal}'),
        gf('region', expr: r'$V{regionTotal}'),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West', 'city': 'A', 'amt': 10},
        <String, Object?>{'region': 'West', 'city': 'A', 'amt': 5},
        <String, Object?>{'region': 'West', 'city': 'B', 'amt': 7},
        <String, Object?>{'region': 'East', 'city': 'C', 'amt': 3},
      ]),
    );
    expect(res.report.bands.map((b) => b.type).toList(), <BandType>[
      BandType.groupHeader, // region West
      BandType.groupHeader, // city A
      BandType.detail,
      BandType.detail,
      BandType.groupFooter, // city A
      BandType.groupHeader, // city B
      BandType.detail,
      BandType.groupFooter, // city B (cascade)
      BandType.groupFooter, // region West (cascade)
      BandType.groupHeader, // region East
      BandType.groupHeader, // city C
      BandType.detail,
      BandType.groupFooter, // city C (end)
      BandType.groupFooter, // region East (end)
    ]);
    String txt(int i) =>
        (res.report.bands[i].elements.single as TextElement).text;
    expect(txt(4), '15.0'); // city A subtotal (pre-reset)
    expect(txt(7), '7.0'); // city B subtotal (inner footer, cascade)
    expect(txt(8), '22.0'); // region West subtotal (outer footer, cascade)
    expect(txt(9), 'East'); // header order: region (outer) first
    expect(txt(10), 'C'); // then city (inner)
    expect(txt(13), '3.0'); // region East subtotal (end)
  });

  test('multiple headers/footers for one group emit in authored order', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        gh('region', text: 'H1'),
        gh('region', text: 'H2'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
        gf('region', text: 'F1'),
        gf('region', text: 'F2'),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
      ]),
    );
    String txt(int i) =>
        (res.report.bands[i].elements.single as TextElement).text;
    expect(txt(0), 'H1');
    expect(txt(1), 'H2');
    expect(txt(3), 'F1');
    expect(txt(4), 'F2');
  });

  test('end-of-data group footers emit before the summary', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        gh('region', text: 'H'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
        gf('region', text: 'GF'),
        ReportBand(type: BandType.summary, height: 10,
            elements: <ReportElement>[t('s', text: 'SUM')]),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
      ]),
    );
    expect(res.report.bands.map((b) => b.type).toList(), <BandType>[
      BandType.groupHeader,
      BandType.detail,
      BandType.groupFooter,
      BandType.summary,
    ]);
  });

  test('a page-scoped reference in a group-band element is an error', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        gh('region', text: 'fb', expr: r'$V{PAGE_NUMBER}'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
      ]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect(
        (res.report.bands.first.elements.single as TextElement).text, 'fb');
  });

  test('duplicate group names fail fast (fill throws)', () {
    expect(
      () => ReportFiller().fill(
        const ReportTemplate(
          name: 'demo',
          page: PageFormat.a4Portrait,
          groups: <ReportGroup>[
            ReportGroup(name: 'region', expression: r'$F{a}'),
            ReportGroup(name: 'region', expression: r'$F{b}'),
          ],
          bands: <ReportBand>[ReportBand(type: BandType.detail, height: 10)],
        ),
        JetInMemoryDataSource(<Map<String, Object?>>[
          <String, Object?>{'a': 1, 'b': 2},
        ]),
      ),
      throwsA(isA<ReportFormatException>()),
    );
  });

  test('groups declared but no group bands emit no group bands (007b parity)',
      () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
        <String, Object?>{'region': 'East'},
      ]),
    );
    expect(res.report.bands.map((b) => b.type).toList(),
        <BandType>[BandType.detail, BandType.detail]);
  });

  test('determinism — re-filling a grouped template yields an equal report', () {
    ReportTemplate make() => ReportTemplate(
          name: 'demo',
          page: PageFormat.a4Portrait,
          groups: const <ReportGroup>[
            ReportGroup(name: 'region', expression: r'$F{region}'),
          ],
          bands: <ReportBand>[
            gh('region', expr: r'$F{region}'),
            ReportBand(type: BandType.detail, height: 10,
                elements: <ReportElement>[t('d', text: '.')]),
            gf('region', text: 'GF'),
          ],
        );
    JetInMemoryDataSource src() => JetInMemoryDataSource(<Map<String, Object?>>[
          <String, Object?>{'region': 'West'},
          <String, Object?>{'region': 'East'},
        ]);
    expect(ReportFiller().fill(make(), src()).report,
        ReportFiller().fill(make(), src()).report);
  });

  test('noData path with groups declared emits only noData (no group bands)', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        gh('region', text: 'H'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
        gf('region', text: 'F'),
        ReportBand(type: BandType.noData, height: 10,
            elements: <ReportElement>[t('n', text: 'ND')]),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(const <Map<String, Object?>>[]),
    );
    // Empty source: only the noData band; no group headers/footers.
    expect(res.report.bands.map((b) => b.type).toList(),
        <BandType>[BandType.noData]);
  });

  test('filled group bands carry their group name; plain bands carry null', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        gh('region', text: 'H'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
        gf('region', text: 'F'),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
      ]),
    );
    final List<FilledBand> b = res.report.bands;
    expect(b[0].type, BandType.groupHeader);
    expect(b[0].group, 'region');
    expect(b[1].type, BandType.detail);
    expect(b[1].group, isNull);
    expect(b.last.type, BandType.groupFooter);
    expect(b.last.group, 'region');
  });

  test('fill normalizes params into FilledReport.params (JetValue; stable)', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
      ],
    );
    FillResult run() => ReportFiller().fill(
          tpl,
          JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{}]),
          params: <String, Object?>{'n': 3, 's': 'hi', 'bad': <int>[1, 2]},
        );
    final FilledReport a = run().report;
    expect(a.params['n'], const JetNumber(3));
    expect(a.params['s'], const JetString('hi'));
    expect(a.params['bad'], isA<JetError>()); // unsupported type -> stable error
    expect(a, run().report); // normalization is stable -> two fills compare equal
  });

  test('a page-scoped reference in a group FOOTER element is an error', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
        gf('region', text: 'fb', expr: r'$V{PAGE_NUMBER}'),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
      ]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    // The footer (emitted at end of data) preserves its authored text.
    expect((res.report.bands.last.elements.single as TextElement).text, 'fb');
  });
}
