// Wrong-type aggregate inputs are surfaced (spec E2, R3/R4) — previously
// silent. Persistent-accumulator sites: master calculator + descendant.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 12);

TextElement _el(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: _r, text: text ?? '', expression: expr);

Diagnostic _match(FillResult res, Pattern p) => res.diagnostics.entries
    .firstWhere((Diagnostic d) => d.message.contains(p),
        orElse: () => fail('no diagnostic matching "$p": '
            '${res.diagnostics.entries}'));

String _summaryText(FillResult res, String id) =>
    (res.report.bands.last.elements.firstWhere((ReportElement e) => e.id == id)
            as TextElement)
        .text;

// ---- master calculator (report-scoped SUM over a wrong-type field) ----

ReportDefinition _masterSumDef() => ReportDefinition(
      name: 'masterSum',
      page: PageFormat.a4Portrait,
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'total',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.report,
        ),
      ],
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 12,
          elements: <ReportElement>[_el('total', expr: r'$V{total}')],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 12,
              elements: <ReportElement>[_el('amt', expr: r'$F{amount}')])),
        ]),
      ),
    );

// ---- descendant SUM at the summary over a wrong-type leaf ----
// (lifted from descendant_summary_fill_test.dart; explicit schema is required
//  because inference does not type nested List<Map> columns as collections.)

const List<FieldDef> _rootSchema = <FieldDef>[
  FieldDef('customerCode', type: JetFieldType.string),
  FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('orderId', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('lineTotal', type: JetFieldType.double),
    ]),
  ]),
];

ReportDefinition _descendantSummaryDef() => ReportDefinition(
      name: 'descSummary',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 12,
          elements: <ReportElement>[
            _el('grand', expr: r'SUM($F{lineTotal})'),
          ],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'orders',
            collectionField: 'orders',
            children: <ScopeNode>[
              NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'line-detail',
                      type: BandType.detail,
                      height: 12,
                      elements: <ReportElement>[
                        _el('lineTotal', expr: r'$F{lineTotal}'),
                      ])),
                ],
              )),
            ],
          )),
        ]),
      ),
    );

void main() {
  test('R3: master-calculator SUM surfaces a row-tagged skip and still sums '
      'the clean rows', () {
    final FillResult res = ReportFiller().fillDefinition(
      _masterSumDef(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'amount': 10.0},
        <String, Object?>{'amount': 'oops'}, // row 2 — wrong type
        <String, Object?>{'amount': 5.0},
      ]),
    );
    final Diagnostic d = _match(res, 'skipped from an aggregate');
    expect(d.severity, DiagnosticSeverity.warning);
    expect(d.message, startsWith('Row 2: '));
    expect(_summaryText(res, 'total'), '15.0',
        reason: 'clean rows still sum; the bad row is isolated');
  });

  test('R3: descendant roll-up SUM surfaces a row-tagged skip', () {
    final FillResult res = ReportFiller().fillDefinition(
      _descendantSummaryDef(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'customerCode': 'A',
          'orders': <Map<String, Object?>>[
            <String, Object?>{
              'orderId': '1',
              'lines': <Map<String, Object?>>[
                <String, Object?>{'lineTotal': 10.0},
                <String, Object?>{'lineTotal': 'bad'}, // wrong type
                <String, Object?>{'lineTotal': 20.0},
              ],
            },
          ],
        },
      ], fields: _rootSchema),
    );
    final Diagnostic d = _match(res, 'skipped from a roll-up aggregate');
    expect(d.message, startsWith('Row 1: '));
    expect(_summaryText(res, 'grand'), '30.0',
        reason: 'clean leaves still sum (10 + 20)');
  });
}
