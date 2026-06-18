// Integration tests for multi-level descendant-leaf folding in nested-scope
// footers (spec 033). The footer aggregate `SUM($F{lineTotal})` sits on the
// `orders` scope (which does not own `lineTotal` directly) and folds over all
// `lineTotal` leaves in the descendant `lines` collection.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
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

/// Builds a 3-level report: root → orders (NestedScope with footer) → lines
/// (NestedScope inside orders).
///
/// The `orders` scope has a footer band with `SUM($F{lineTotal})`.
/// `lineTotal` is NOT a field of an `orders` row — it lives in the
/// grandchild `lines` collection rows. The footer folds over all descendant
/// `lines` leaves within the `orders` collection for that master row.
ReportDefinition _makeDefinition() => ReportDefinition(
      name: 'descendantFooterTest',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'orders',
              collectionField: 'orders',
              // Footer with a descendant-leaf aggregate on `lineTotal`.
              // lineTotal belongs to `lines` rows, not `orders` rows.
              footer: Band(
                id: 'orders-footer',
                type: BandType.groupFooter,
                height: 12,
                elements: <ReportElement>[
                  _el('orderTotal', expr: r'SUM($F{lineTotal})'),
                ],
              ),
              children: <ScopeNode>[
                // Detail band for each order row
                BandNode(Band(
                  id: 'order-detail',
                  type: BandType.detail,
                  height: 12,
                  elements: <ReportElement>[
                    _el('orderId', expr: r'$F{orderId}'),
                  ],
                )),
                // Nested lines scope — each line has `lineTotal`
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
  // The `orders` NestedScope is a direct child of the root scope, so there is
  // ONE footer per master (customer) row — it sums ALL `lineTotal` values across
  // every order and every line belonging to that customer.
  //
  // Customer 1 has two orders:
  //   order A: lines [10, 20] → contributes 30
  //   order B: lines [5]     → contributes  5
  //   → footer total for customer 1: 35
  //
  // Customer 2 has one order:
  //   order C: lines [100, 200] → contributes 300
  //   → footer total for customer 2: 300
  test(
      'descendant footer SUM folds all lineTotal leaves across all orders of '
      'each customer (multi-level, resets per master row)', () {
    final FillResult res = ReportFiller().fillDefinition(
      _makeDefinition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        // Customer 1
        <String, Object?>{
          'orders': <Map<String, Object?>>[
            <String, Object?>{
              'orderId': 'A',
              'lines': <Map<String, Object?>>[
                <String, Object?>{'lineTotal': 10.0},
                <String, Object?>{'lineTotal': 20.0},
              ],
            },
            <String, Object?>{
              'orderId': 'B',
              'lines': <Map<String, Object?>>[
                <String, Object?>{'lineTotal': 5.0},
              ],
            },
          ],
        },
        // Customer 2
        <String, Object?>{
          'orders': <Map<String, Object?>>[
            <String, Object?>{
              'orderId': 'C',
              'lines': <Map<String, Object?>>[
                <String, Object?>{'lineTotal': 100.0},
                <String, Object?>{'lineTotal': 200.0},
              ],
            },
          ],
        },
      ]),
    );

    // Collect footer bands (groupFooter type) in emission order.
    final List<FilledBand> footers = res.report.bands
        .where((FilledBand b) => b.type == BandType.groupFooter)
        .toList();

    // Expect 2 footers: one per master (customer) row.
    expect(footers, hasLength(2),
        reason: 'one footer per customer: cust1=35, cust2=300');

    String footerText(FilledBand b) =>
        (b.elements.firstWhere((e) => e.id == 'orderTotal') as TextElement)
            .text;

    // Customer 1: orders A (10+20=30) + B (5) = 35 total lineTotals
    expect(footerText(footers[0]), '35.0',
        reason: 'customer 1: SUM(10 + 20 + 5) = 35');
    // Customer 2: order C (100+200=300)
    expect(footerText(footers[1]), '300.0',
        reason: 'customer 2: SUM(100 + 200) = 300');
  });

  test('empty descendant collection renders 0.0 (no lines under the order)',
      () {
    final FillResult res = ReportFiller().fillDefinition(
      _makeDefinition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'orders': <Map<String, Object?>>[
            <String, Object?>{
              'orderId': 'X',
              'lines': <Map<String, Object?>>[],
            },
          ],
        },
      ]),
    );

    // The orders collection is non-empty (1 order row), so a footer is emitted.
    final List<FilledBand> footers = res.report.bands
        .where((FilledBand b) => b.type == BandType.groupFooter)
        .toList();

    expect(footers, hasLength(1), reason: 'footer emitted for the order row');

    final String text =
        (footers.first.elements.firstWhere((e) => e.id == 'orderTotal')
                as TextElement)
            .text;
    // An empty fold of SUM is 0.0 (VariableAccumulator initial value).
    expect(text, '0.0', reason: 'no lines → sum is 0');
  });
}
