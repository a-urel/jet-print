// Integration tests for descendant-leaf folding at the summary (report-reset)
// and root group footer (group-reset) bands — spec 033. The authoring form
// `SUM($F{lineTotal})` in those bands folds over every lineTotal leaf
// reachable from the master scope via the path [orders, lines].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 12);

TextElement _el(String id, {String? text, String? expr}) => TextElement(
      id: id,
      bounds: _r,
      text: text ?? '',
      expression: expr,
    );

// An explicit schema declaring the nested shape, so resolveAggregatePath can
// descend [orders, lines] to find lineTotal. Inference now types nested
// List<Map> columns as collections too (SC-006), so a declared schema is no
// longer required — the final test in this file proves the inferred path.
const List<FieldDef> _rootSchema = <FieldDef>[
  FieldDef('customerCode', type: JetFieldType.string),
  FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('orderId', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('lineTotal', type: JetFieldType.double),
    ]),
  ]),
];

/// Two-customer fixture:
/// - Customer A: order 1 (lines: 10, 20 = 30), order 2 (lines: 5)   → A total = 35
/// - Customer B: order 3 (lines: 100, 200 = 300)                    → B total = 300
/// Grand total = 335; total line count = 5; AVG = 335/5 = 67.
///
/// We also include Customer C with NO orders to verify it contributes nothing
/// to the summary.
List<Map<String, Object?>> _rows() => <Map<String, Object?>>[
      <String, Object?>{
        'customerCode': 'A',
        'orders': <Map<String, Object?>>[
          <String, Object?>{
            'orderId': '1',
            'lines': <Map<String, Object?>>[
              <String, Object?>{'lineTotal': 10.0},
              <String, Object?>{'lineTotal': 20.0},
            ],
          },
          <String, Object?>{
            'orderId': '2',
            'lines': <Map<String, Object?>>[
              <String, Object?>{'lineTotal': 5.0},
            ],
          },
        ],
      },
      <String, Object?>{
        'customerCode': 'B',
        'orders': <Map<String, Object?>>[
          <String, Object?>{
            'orderId': '3',
            'lines': <Map<String, Object?>>[
              <String, Object?>{'lineTotal': 100.0},
              <String, Object?>{'lineTotal': 200.0},
            ],
          },
        ],
      },
      <String, Object?>{
        'customerCode': 'C',
        'orders': <Map<String, Object?>>[],
      },
    ];

/// Builds a report with:
/// - a `customer` root group (keyed on customerCode) with a footer containing
///   [footerExpr],
/// - a summary band containing [summaryExpr].
ReportDefinition _makeDefinition({
  required String footerExpr,
  required String summaryExpr,
}) =>
    ReportDefinition(
      name: 'descendantSummaryTest',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 12,
          elements: <ReportElement>[
            _el('summaryTotal', expr: summaryExpr),
          ],
        ),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'customer',
              name: 'customer',
              key: r'$F{customerCode}',
              footer: Band(
                id: 'customer-footer',
                type: BandType.groupFooter,
                height: 12,
                elements: <ReportElement>[
                  _el('customerTotal', expr: footerExpr),
                ],
              ),
            ),
          ],
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'orders',
              collectionField: 'orders',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'order-detail',
                  type: BandType.detail,
                  height: 12,
                  elements: <ReportElement>[
                    _el('orderId', expr: r'$F{orderId}'),
                  ],
                )),
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
                      ],
                    )),
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  group('descendant SUM at summary and root group footer', () {
    test(
        'customer group footer renders per-customer lineTotal sum; '
        'summary renders grand total', () {
      final FillResult res = ReportFiller().fillDefinition(
        _makeDefinition(
          footerExpr: r'SUM($F{lineTotal})',
          summaryExpr: r'SUM($F{lineTotal})',
        ),
        JetInMemoryDataSource(_rows(), fields: _rootSchema),
      );

      // Collect group footers in emission order (customer A then B then C).
      final List<FilledBand> footers = res.report.bands
          .where((FilledBand b) => b.type == BandType.groupFooter)
          .toList();

      // Three customers → three group footers.
      expect(footers, hasLength(3),
          reason: 'one footer per customer: A=35, B=300, C=0');

      String footerText(FilledBand b) =>
          (b.elements.firstWhere((ReportElement e) => e.id == 'customerTotal')
                  as TextElement)
              .text;

      // Customer A: orders 1 (10+20=30) + 2 (5) = 35
      expect(footerText(footers[0]), '35.0',
          reason: 'customer A: SUM(10 + 20 + 5) = 35');
      // Customer B: order 3 (100+200=300)
      expect(footerText(footers[1]), '300.0',
          reason: 'customer B: SUM(100 + 200) = 300');
      // Customer C: no orders → 0
      expect(footerText(footers[2]), '0.0',
          reason: 'customer C: no lines → sum = 0');

      // Summary should have grand total 335.
      final FilledBand summary = res.report.bands.last;
      expect(summary.type, BandType.summary);
      final String summaryText = (summary.elements
                  .firstWhere((ReportElement e) => e.id == 'summaryTotal')
              as TextElement)
          .text;
      expect(summaryText, '335.0',
          reason: 'grand total = 10+20+5+100+200 = 335');

      // No diagnostics errors.
      expect(res.diagnostics.hasErrors, isFalse,
          reason: 'no errors expected: ${res.diagnostics.entries}');
    });

    test(
        'AVG at summary = total-sum / total-line-count (flat average over all leaves); '
        'empty-orders customer contributes nothing', () {
      final FillResult res = ReportFiller().fillDefinition(
        _makeDefinition(
          footerExpr: r'SUM($F{lineTotal})', // not under test here
          summaryExpr: r'AVG($F{lineTotal})',
        ),
        JetInMemoryDataSource(_rows(), fields: _rootSchema),
      );

      final FilledBand summary = res.report.bands.last;
      expect(summary.type, BandType.summary);
      final String summaryText = (summary.elements
                  .firstWhere((ReportElement e) => e.id == 'summaryTotal')
              as TextElement)
          .text;
      // 5 lines: 10, 20, 5, 100, 200. Sum=335. AVG = 335/5 = 67.0
      expect(summaryText, '67.0',
          reason: 'flat AVG over all 5 lines = 335 / 5 = 67');

      expect(res.diagnostics.hasErrors, isFalse);
    });

    test(
        'descendant SUM works over an INFERRED schema too (no explicit '
        'fields:) — SC-006', () {
      // Same report, but the source carries NO explicit schema: the nested
      // orders/lines collections are inferred. The root-scope descend must
      // still resolve [orders, lines] and fold identically to the declared
      // case above (35 / 300 / 0; grand total 335).
      final FillResult res = ReportFiller().fillDefinition(
        _makeDefinition(
          footerExpr: r'SUM($F{lineTotal})',
          summaryExpr: r'SUM($F{lineTotal})',
        ),
        JetInMemoryDataSource(_rows()), // inferred, not declared
      );

      String footerText(FilledBand b) =>
          (b.elements.firstWhere((ReportElement e) => e.id == 'customerTotal')
                  as TextElement)
              .text;
      final List<String> footers = <String>[
        for (final FilledBand b in res.report.bands)
          if (b.type == BandType.groupFooter) footerText(b),
      ];
      expect(footers, <String>['35.0', '300.0', '0.0'],
          reason: 'inferred schema descends [orders, lines] like a declared '
              'one');

      final FilledBand summary = res.report.bands.last;
      final String summaryText = (summary.elements
                  .firstWhere((ReportElement e) => e.id == 'summaryTotal')
              as TextElement)
          .text;
      expect(summaryText, '335.0',
          reason: 'grand total over an inferred schema = 335');
      expect(res.diagnostics.hasErrors, isFalse);
    });
  });
}
