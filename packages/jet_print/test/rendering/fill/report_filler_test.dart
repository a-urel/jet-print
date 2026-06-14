// ReportFiller: the Fill data pass — flat bands (007b) + grouping (007c),
// migrated to the reified model + native fillDefinition API (spec 024).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart' as domain;
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_validation.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect r = JetRect(x: 0, y: 0, width: 100, height: 10);

TextElement t(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: r, text: text ?? '', expression: expr);

// A group-header band for group [group] (the band the GroupLevel owns).
Band gh(String group, {String? text, String? expr}) => Band(
      id: 'gh-$group',
      type: BandType.groupHeader,
      height: 10,
      elements: <ReportElement>[t('h-$group', text: text, expr: expr)],
    );
// A group-footer band for group [group].
Band gf(String group, {String? text, String? expr}) => Band(
      id: 'gf-$group',
      type: BandType.groupFooter,
      height: 10,
      elements: <ReportElement>[t('f-$group', text: text, expr: expr)],
    );

ReportDefinition template({
  List<ReportElement> title = const <ReportElement>[],
  List<ReportElement> detail = const <ReportElement>[],
  List<ReportElement> summary = const <ReportElement>[],
  List<ReportElement> noData = const <ReportElement>[],
  List<ReportVariable> variables = const <ReportVariable>[],
  List<GroupLevel> groups = const <GroupLevel>[],
}) =>
    ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      variables: variables,
      body: ReportBody(
        title: title.isEmpty
            ? null
            : Band(
                id: 'body/title',
                type: BandType.title,
                height: 10,
                elements: title),
        summary: summary.isEmpty
            ? null
            : Band(
                id: 'body/summary',
                type: BandType.summary,
                height: 10,
                elements: summary),
        noData: noData.isEmpty
            ? null
            : Band(
                id: 'body/noData',
                type: BandType.noData,
                height: 10,
                elements: noData),
        root: DetailScope(
          id: 'root',
          groups: groups,
          children: <ScopeNode>[
            if (detail.isNotEmpty)
              BandNode(Band(
                  id: 'detail',
                  type: BandType.detail,
                  height: 10,
                  elements: detail)),
          ],
        ),
      ),
    );

void main() {
  test('flat data golden — title once, one detail per row, summary once', () {
    final FillResult res = ReportFiller().fillDefinition(
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
    final List<BandType> types = res.report.bands.map((b) => b.type).toList();
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
    final FillResult res = ReportFiller().fillDefinition(
      template(
        detail: <ReportElement>[t('d', expr: r'$V{total}')],
        summary: <ReportElement>[t('s', expr: r'$V{total}')],
        variables: const <ReportVariable>[
          ReportVariable(
              name: 'total',
              expression: r'$F{amount}',
              calculation: JetCalculation.sum),
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
    final FillResult res = ReportFiller().fillDefinition(
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
    final FillResult res = ReportFiller().fillDefinition(
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
    final FillResult res = ReportFiller().fillDefinition(
      template(
        detail: <ReportElement>[t('d', text: '.')],
        variables: const <ReportVariable>[
          ReportVariable(
              name: 'total',
              expression: r'$F{typo}',
              calculation: JetCalculation.sum),
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
    final FillResult res = ReportFiller().fillDefinition(
      template(detail: <ReportElement>[
        t('d', text: 'fb', expr: r'$V{PAGE_NUMBER}')
      ]),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'x': 1}
      ]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect((res.report.bands[0].elements.single as TextElement).text, 'fb');
  });

  test('page-scoped reference in a variable expression is an error', () {
    final FillResult res = ReportFiller().fillDefinition(
      template(
        detail: <ReportElement>[t('d', text: '.')],
        variables: const <ReportVariable>[
          ReportVariable(name: 'v', expression: r'$V{PAGE_NUMBER}'),
        ],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'x': 1}
      ]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect(
        res.diagnostics.entries.any((e) => e.message.contains('variable "v"')),
        isTrue); // site-tagged
  });

  test('page-scoped reference in a group expression is an error', () {
    final FillResult res = ReportFiller().fillDefinition(
      template(
        detail: <ReportElement>[t('d', text: '.')],
        groups: const <GroupLevel>[
          GroupLevel(id: 'g', name: 'g', key: r'$V{PAGE_NUMBER}'),
        ],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'x': 1}
      ]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect(res.diagnostics.entries.any((e) => e.message.contains('group "g"')),
        isTrue); // site-tagged
  });

  test('page-scoped reference in a noData element is an error', () {
    final FillResult res = ReportFiller().fillDefinition(
      template(noData: <ReportElement>[
        t('n', text: 'none', expr: r'$V{PAGE_NUMBER}')
      ]),
      JetInMemoryDataSource(const <Map<String, Object?>>[]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect(
        (res.report.bands.single.elements.single as TextElement).text, 'none');
  });

  test('a malformed variable expression fails fast (throws)', () {
    expect(
      () => ReportFiller().fillDefinition(
        template(
          detail: <ReportElement>[t('d', text: '.')],
          variables: const <ReportVariable>[
            ReportVariable(name: 'v', expression: r'CONCAT('),
          ],
        ),
        JetInMemoryDataSource(<Map<String, Object?>>[
          <String, Object?>{'x': 1}
        ]),
      ),
      throwsA(isA<ExpressionException>()),
    );
  });

  test('determinism — re-filling identical inputs yields an equal report', () {
    ReportDefinition make() =>
        template(detail: <ReportElement>[t('d', expr: r'$F{n}')]);
    JetInMemoryDataSource src() => JetInMemoryDataSource(<Map<String, Object?>>[
          <String, Object?>{'n': 'a'}
        ]);
    expect(ReportFiller().fillDefinition(make(), src()).report,
        ReportFiller().fillDefinition(make(), src()).report);
  });

  test('title has no row context — \$F{} blanks silently', () {
    final FillResult res = ReportFiller().fillDefinition(
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
    final FillResult res = ReportFiller().fillDefinition(
      template(
        title: <ReportElement>[t('h', text: 'fb', expr: r'$V{PAGE_NUMBER}')],
        detail: <ReportElement>[t('d', text: '.')],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'x': 1}
      ]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    // authored text preserved (not blanked, not !ERR)
    expect((res.report.bands.first.elements.single as TextElement).text, 'fb');
  });

  test('page-scoped reference in a summary element is an error', () {
    final FillResult res = ReportFiller().fillDefinition(
      template(
        summary: <ReportElement>[t('s', text: 'fb', expr: r'$V{PAGE_NUMBER}')],
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'x': 1}
      ]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect((res.report.bands.last.elements.single as TextElement).text, 'fb');
  });

  test('single group: header/detail/footer sequence with pre-reset subtotal',
      () {
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      variables: const <ReportVariable>[
        ReportVariable(
            name: 'regionTotal',
            expression: r'$F{amt}',
            calculation: JetCalculation.sum,
            resetScope: VariableResetScope.group,
            resetGroup: 'region'),
      ],
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              header: gh('region', expr: r'$F{region}'),
              footer: gf('region', expr: r'$V{regionTotal}'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', expr: r'$V{regionTotal}')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
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
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              header: gh('region', expr: r'$F{city}'),
              footer: gf('region', expr: r'$F{city}'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', text: '.')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
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
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
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
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              header: gh('region', expr: r'$F{region}'),
              footer: gf('region', expr: r'$V{regionTotal}'),
            ),
            GroupLevel(
              id: 'city',
              name: 'city',
              key: r'$F{city}',
              header: gh('city', expr: r'$F{city}'),
              footer: gf('city', expr: r'$V{cityTotal}'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', text: '.')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
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
    // In the reified model a GroupLevel owns at most one header and one footer.
    // The legacy "two group-header bands / two group-footer bands" is faithfully
    // a header band carrying two elements (H1, H2) and a footer band carrying
    // two (F1, F2): the same authored-order emission within the group's open/
    // close, byte-identical to two same-height stacked bands' element stream.
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              header: Band(
                  id: 'gh-region',
                  type: BandType.groupHeader,
                  height: 20,
                  elements: <ReportElement>[
                    t('h1-region', text: 'H1'),
                    t('h2-region', text: 'H2'),
                  ]),
              footer: Band(
                  id: 'gf-region',
                  type: BandType.groupFooter,
                  height: 20,
                  elements: <ReportElement>[
                    t('f1-region', text: 'F1'),
                    t('f2-region', text: 'F2'),
                  ]),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', text: '.')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
      ]),
    );
    // header band first, footer band last; their elements in authored order.
    final List<TextElement> headerEls =
        res.report.bands.first.elements.cast<TextElement>();
    final List<TextElement> footerEls =
        res.report.bands.last.elements.cast<TextElement>();
    expect(headerEls.map((TextElement e) => e.text).toList(),
        <String>['H1', 'H2']);
    expect(footerEls.map((TextElement e) => e.text).toList(),
        <String>['F1', 'F2']);
  });

  test('end-of-data group footers emit before the summary', () {
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(
            id: 'body/summary',
            type: BandType.summary,
            height: 10,
            elements: <ReportElement>[t('s', text: 'SUM')]),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              header: gh('region', text: 'H'),
              footer: gf('region', text: 'GF'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', text: '.')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
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
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              header: gh('region', text: 'fb', expr: r'$V{PAGE_NUMBER}'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', text: '.')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
      ]),
    );
    expect(res.diagnostics.hasErrors, isTrue);
    expect((res.report.bands.first.elements.single as TextElement).text, 'fb');
  });

  test('duplicate group names are rejected by author-time validation', () {
    // The legacy "fill throws ReportFormatException on duplicate group names"
    // contract moved to author-time validate() in the reified model, which
    // reports the same invariant violation as an error Diagnostic (so the
    // designer can hold a transient duplicate mid-rename without exceptions).
    // Intent preserved: duplicate group names are detected and rejected.
    final ReportDefinition def = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(id: 'g1', name: 'region', key: r'$F{a}'),
            GroupLevel(id: 'g2', name: 'region', key: r'$F{b}'),
          ],
        ),
      ),
    );
    final List<domain.Diagnostic> issues = validate(def);
    expect(
        issues.any((domain.Diagnostic d) =>
            d.severity == domain.DiagnosticSeverity.error &&
            d.message.contains('duplicate group name "region"')),
        isTrue);
  });

  test('groups declared but no group bands emit no group bands (007b parity)',
      () {
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(id: 'region', name: 'region', key: r'$F{region}'),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[
                  TextElement(id: 'd', bounds: r, text: '.')
                ])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
        <String, Object?>{'region': 'East'},
      ]),
    );
    expect(res.report.bands.map((b) => b.type).toList(),
        <BandType>[BandType.detail, BandType.detail]);
  });

  test('determinism — re-filling a grouped template yields an equal report',
      () {
    ReportDefinition make() => ReportDefinition(
          name: 'demo',
          page: PageFormat.a4Portrait,
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              groups: <GroupLevel>[
                GroupLevel(
                  id: 'region',
                  name: 'region',
                  key: r'$F{region}',
                  header: gh('region', expr: r'$F{region}'),
                  footer: gf('region', text: 'GF'),
                ),
              ],
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'detail',
                    type: BandType.detail,
                    height: 10,
                    elements: <ReportElement>[t('d', text: '.')])),
              ],
            ),
          ),
        );
    JetInMemoryDataSource src() => JetInMemoryDataSource(<Map<String, Object?>>[
          <String, Object?>{'region': 'West'},
          <String, Object?>{'region': 'East'},
        ]);
    expect(ReportFiller().fillDefinition(make(), src()).report,
        ReportFiller().fillDefinition(make(), src()).report);
  });

  test('noData path with groups declared emits only noData (no group bands)',
      () {
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        noData: Band(
            id: 'body/noData',
            type: BandType.noData,
            height: 10,
            elements: <ReportElement>[t('n', text: 'ND')]),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              header: gh('region', text: 'H'),
              footer: gf('region', text: 'F'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', text: '.')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
      tpl,
      JetInMemoryDataSource(const <Map<String, Object?>>[]),
    );
    // Empty source: only the noData band; no group headers/footers.
    expect(res.report.bands.map((b) => b.type).toList(),
        <BandType>[BandType.noData]);
  });

  test('filled group bands carry their group name; plain bands carry null', () {
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              header: gh('region', text: 'H'),
              footer: gf('region', text: 'F'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', text: '.')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
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

  test('fill normalizes params into FilledReport.params (JetValue; stable)',
      () {
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[
                  TextElement(id: 'd', bounds: r, text: '.')
                ])),
          ],
        ),
      ),
    );
    FillResult run() => ReportFiller().fillDefinition(
          tpl,
          JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{}]),
          params: <String, Object?>{
            'n': 3,
            's': 'hi',
            'bad': <int>[1, 2]
          },
        );
    final FilledReport a = run().report;
    expect(a.params['n'], const JetNumber(3));
    expect(a.params['s'], const JetString('hi'));
    expect(
        a.params['bad'], isA<JetError>()); // unsupported type -> stable error
    expect(
        a, run().report); // normalization is stable -> two fills compare equal
  });

  test('a page-scoped reference in a group FOOTER element is an error', () {
    final ReportDefinition tpl = ReportDefinition(
      name: 'demo',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'region',
              name: 'region',
              key: r'$F{region}',
              footer: gf('region', text: 'fb', expr: r'$V{PAGE_NUMBER}'),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 10,
                elements: <ReportElement>[t('d', text: '.')])),
          ],
        ),
      ),
    );
    final FillResult res = ReportFiller().fillDefinition(
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
