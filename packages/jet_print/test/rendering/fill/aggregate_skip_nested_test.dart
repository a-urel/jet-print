// Wrong-type aggregate inputs at the FRESH-accumulator sites are surfaced
// (spec E2): published totals (030) and nested-scope footers (029/033).
import 'package:flutter_test/flutter_test.dart';
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
import 'package:jet_print/src/domain/scope_total.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 12);

TextElement _el(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: _r, text: text ?? '', expression: expr);

Diagnostic _match(FillResult res, Pattern p) => res.diagnostics.entries
    .firstWhere((Diagnostic d) => d.message.contains(p),
        orElse: () => fail('no diagnostic matching "$p": '
            '${res.diagnostics.entries}'));

// ---- published total (030): scope 'lines' publishes SUM($F{amount}) ----

ReportDefinition _scopeTotalDef() => ReportDefinition(
      name: 'scopeTotal',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'lines',
            collectionField: 'lines',
            totals: const <ScopeTotal>[ScopeTotal('lineSum', r'SUM($F{amount})')],
            children: <ScopeNode>[
              BandNode(Band(
                  id: 'line',
                  type: BandType.detail,
                  height: 12,
                  elements: <ReportElement>[_el('a', expr: r'$F{amount}')])),
            ],
          )),
        ]),
      ),
    );

// ---- nested footer (029/033): orders footer SUM($F{lineTotal}) ----
// (lifted from descendant_footer_fill_test.dart)

ReportDefinition _nestedFooterDef() => ReportDefinition(
      name: 'nestedFooter',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'orders',
            collectionField: 'orders',
            footer: Band(
              id: 'orders-footer',
              type: BandType.groupFooter,
              height: 12,
              elements: <ReportElement>[
                _el('orderTotal', expr: r'SUM($F{lineTotal})'),
              ],
            ),
            children: <ScopeNode>[
              BandNode(Band(
                  id: 'order-detail',
                  type: BandType.detail,
                  height: 12,
                  elements: <ReportElement>[_el('orderId', expr: r'$F{orderId}')])),
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
  test('R3: a published total surfaces a row-tagged skip', () {
    final FillResult res = ReportFiller().fillDefinition(
      _scopeTotalDef(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Map<String, Object?>>[
            <String, Object?>{'amount': 10.0},
            <String, Object?>{'amount': 'x'}, // wrong type
            <String, Object?>{'amount': 5.0},
          ],
        },
      ]),
    );
    final Diagnostic d = _match(res, 'published total "lineSum"');
    expect(d.severity, DiagnosticSeverity.warning);
    expect(d.message, startsWith('Row 1: '));
    expect(d.message, contains('skipped'));
  });

  test('R3: a nested-scope footer aggregate surfaces a row-tagged skip', () {
    final FillResult res = ReportFiller().fillDefinition(
      _nestedFooterDef(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'orders': <Map<String, Object?>>[
            <String, Object?>{
              'orderId': 'A',
              'lines': <Map<String, Object?>>[
                <String, Object?>{'lineTotal': 10.0},
                <String, Object?>{'lineTotal': 'nope'}, // wrong type
              ],
            },
          ],
        },
      ]),
    );
    final Diagnostic d = _match(res, 'footer aggregate "orderTotal"');
    expect(d.message, startsWith('Row 1: '));
    expect(d.message, contains('skipped'));
  });
}
