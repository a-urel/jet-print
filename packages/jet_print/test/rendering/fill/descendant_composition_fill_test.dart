// FR-008: compound/embedded aggregates and multiple operands at different depths
// each resolve and fold independently (spec 033).
//
// Verifies that `liftDescendantAggregates` correctly reuses the spec-032
// `_expandInlineAggregates` scanner so that aggregate SUB-TERMS are lifted
// correctly, e.g.:
//   - `SUM($F{lineTotal}) * 1.1`  → lift SUM sub-term, keep `* 1.1`
//   - `SUM($F{lineTotal}) + COUNT($F{orderNo})`  → lift both sub-terms
//     independently along their respective descend paths
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

// Explicit schema: inference does NOT type nested List<Map> columns as
// collections, so we must declare the nested shape explicitly.
//   - orders.orderNo is one level down (path [orders])
//   - orders.lines.lineTotal is two levels down (path [orders, lines])
const List<FieldDef> _rootSchema = <FieldDef>[
  FieldDef('customerCode', type: JetFieldType.string),
  FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('orderNo', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('lineTotal', type: JetFieldType.double),
    ]),
  ]),
];

/// Two-customer fixture:
/// - Customer A: order 1 (lines: 10, 20 = 30), order 2 (lines: 5)  → lineSum=35, orderCount=2
/// - Customer B: order 3 (lines: 100, 200 = 300)                   → lineSum=300, orderCount=1
/// Customer C: no orders → lineSum=0, orderCount=0
///
/// Assertions:
///   `SUM([lineTotal]) * 1.1`:
///     A → 35 * 1.1 = 38.5
///     B → 300 * 1.1 = 330.0
///     C → 0 * 1.1  = 0.0
///   `SUM([lineTotal]) + COUNT([orderNo])`:
///     A → 35 + 2 = 37.0
///     B → 300 + 1 = 301.0
///     C → 0 + 0  = 0.0
List<Map<String, Object?>> _rows() => <Map<String, Object?>>[
      <String, Object?>{
        'customerCode': 'A',
        'orders': <Map<String, Object?>>[
          <String, Object?>{
            'orderNo': 'O1',
            'lines': <Map<String, Object?>>[
              <String, Object?>{'lineTotal': 10.0},
              <String, Object?>{'lineTotal': 20.0},
            ],
          },
          <String, Object?>{
            'orderNo': 'O2',
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
            'orderNo': 'O3',
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

/// Builds a report with a customer root group.  The group footer has TWO
/// elements with compound/multi-operand expressions:
///   - `scaledTotal`: `SUM($F{lineTotal}) * 1.1`   (sub-term lift, scalar mult)
///   - `sumPlusCount`: `SUM($F{lineTotal}) + COUNT($F{orderNo})`  (two operands
///     at different depths: lineTotal @ [orders,lines], orderNo @ [orders])
ReportDefinition _makeDefinition() => ReportDefinition(
      name: 'descendantCompositionTest',
      page: PageFormat.a4Portrait,
      body: ReportBody(
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
                  _el('whichCustomer', expr: r'$F{customerCode}'),
                  _el('scaledTotal', expr: r'SUM($F{lineTotal}) * 1.1'),
                  _el('sumPlusCount',
                      expr: r'SUM($F{lineTotal}) + COUNT($F{orderNo})'),
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
                    _el('orderNo', expr: r'$F{orderNo}'),
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
  group('descendant aggregate composition (FR-008)', () {
    late FillResult res;
    late List<FilledBand> footers;

    setUp(() {
      res = ReportFiller().fillDefinition(
        _makeDefinition(),
        JetInMemoryDataSource(_rows(), fields: _rootSchema),
      );

      footers = res.report.bands
          .where((FilledBand b) => b.type == BandType.groupFooter)
          .toList();
    });

    test('emits one footer per customer (3 customers)', () {
      expect(footers, hasLength(3), reason: 'one footer per customer: A, B, C');
    });

    test('no diagnostics errors', () {
      expect(res.diagnostics.hasErrors, isFalse,
          reason: 'no errors expected: ${res.diagnostics.entries}');
    });

    // Resolves the rendered customerCode from a footer band so that each
    // value assertion is tied to a verified customer identity, not just a
    // positional index.
    String customerCode(FilledBand b) =>
        (b.elements.firstWhere((ReportElement e) => e.id == 'whichCustomer')
                as TextElement)
            .text;

    FilledBand footerFor(String code) {
      final FilledBand? b =
          footers.where((FilledBand f) => customerCode(f) == code).firstOrNull;
      expect(b, isNotNull,
          reason: 'expected a footer for customer $code but none found');
      return b!;
    }

    group('SUM([lineTotal]) * 1.1 — sub-term lift with scalar multiplier', () {
      String scaledText(FilledBand b) =>
          (b.elements.firstWhere((ReportElement e) => e.id == 'scaledTotal')
                  as TextElement)
              .text;

      test('customer A: (10+20+5) * 1.1 = 38.5', () {
        final FilledBand footer = footerFor('A');
        // SUM of all lineTotal leaves under customer A = 35; * 1.1 = 38.5
        expect(scaledText(footer), '38.5',
            reason: 'A: SUM(10+20+5)=35, 35*1.1=38.5');
      });

      test('customer B: (100+200) * 1.1 = 330.0', () {
        final FilledBand footer = footerFor('B');
        expect(scaledText(footer), '330.0',
            reason: 'B: SUM(100+200)=300, 300*1.1=330.0');
      });

      test('customer C (no orders): 0 * 1.1 = 0.0', () {
        final FilledBand footer = footerFor('C');
        expect(scaledText(footer), '0.0',
            reason: 'C: no lines → SUM=0, 0*1.1=0.0');
      });
    });

    group(
        'SUM([lineTotal]) + COUNT([orderNo]) — two operands at different depths',
        () {
      String sumPlusCountText(FilledBand b) =>
          (b.elements.firstWhere((ReportElement e) => e.id == 'sumPlusCount')
                  as TextElement)
              .text;

      // lineTotal is path [orders, lines] — two levels down
      // orderNo  is path [orders]         — one level down
      // Each sub-term lifts independently via _expandInlineAggregates.

      test('customer A: SUM(lineTotal)=35 + COUNT(orderNo)=2 = 37.0', () {
        final FilledBand footer = footerFor('A');
        expect(sumPlusCountText(footer), '37.0', reason: 'A: 35 + 2 = 37');
      });

      test('customer B: SUM(lineTotal)=300 + COUNT(orderNo)=1 = 301.0', () {
        final FilledBand footer = footerFor('B');
        expect(sumPlusCountText(footer), '301.0', reason: 'B: 300 + 1 = 301');
      });

      test('customer C (no orders): SUM=0 + COUNT=0 = 0.0', () {
        final FilledBand footer = footerFor('C');
        expect(sumPlusCountText(footer), '0.0', reason: 'C: 0 + 0 = 0');
      });
    });
  });
}
