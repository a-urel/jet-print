// Tests that an inline aggregate whose operand is AMBIGUOUS (appears in ≥2
// sibling descendant collections) renders the fallback token (#ERROR) rather
// than a number — spec 033 / FR-010.
//
// Also covers additional aggregation functions (COUNT at summary, AVG at a
// group footer) to close gaps flagged during the Task 5 review.
//
// FIXTURE NOTE: source-level schema inference does NOT type nested List<Map>
// columns as collections. Every fixture below supplies an EXPLICIT FieldDef
// schema so that resolveAggregatePath descends the declared collection tree
// and returns Ambiguous when the operand name appears under two sibling
// collections.
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

// ---------------------------------------------------------------------------
// Schema A: ambiguous at the MASTER scope
//
// The master row has two sibling collections — `salesLines` and `payments` —
// both containing a field named `amount`. resolveAggregatePath(rootFields,
// 'amount') returns Ambiguous (two distinct paths).
// ---------------------------------------------------------------------------

const List<FieldDef> _ambiguousRootSchema = <FieldDef>[
  FieldDef('customerId', type: JetFieldType.string),
  FieldDef('salesLines', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('amount', type: JetFieldType.double),
  ]),
  FieldDef('payments', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('amount', type: JetFieldType.double),
  ]),
];

List<Map<String, Object?>> _ambiguousRootRows() => <Map<String, Object?>>[
      <String, Object?>{
        'customerId': 'C1',
        'salesLines': <Map<String, Object?>>[
          <String, Object?>{'amount': 50.0},
          <String, Object?>{'amount': 30.0},
        ],
        'payments': <Map<String, Object?>>[
          <String, Object?>{'amount': 80.0},
        ],
      },
      <String, Object?>{
        'customerId': 'C2',
        'salesLines': <Map<String, Object?>>[
          <String, Object?>{'amount': 100.0},
        ],
        'payments': <Map<String, Object?>>[
          <String, Object?>{'amount': 100.0},
        ],
      },
    ];

/// Report with a `customer` root group (keyed on customerId), whose footer
/// and the summary both use SUM($F{amount}) — ambiguous at the master scope.
ReportDefinition _makeAmbiguousSummaryDef() => ReportDefinition(
      name: 'ambiguousSummaryTest',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 12,
          elements: <ReportElement>[
            _el('grandTotal', expr: r'SUM($F{amount})'),
          ],
        ),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'customer',
              name: 'customer',
              key: r'$F{customerId}',
              footer: Band(
                id: 'customer-footer',
                type: BandType.groupFooter,
                height: 12,
                elements: <ReportElement>[
                  _el('customerTotal', expr: r'SUM($F{amount})'),
                ],
              ),
            ),
          ],
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'salesLines',
              collectionField: 'salesLines',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'sales-detail',
                  type: BandType.detail,
                  height: 12,
                  elements: <ReportElement>[
                    _el('saleAmount', expr: r'$F{amount}'),
                  ],
                )),
              ],
            )),
            NestedScope(DetailScope(
              id: 'payments',
              collectionField: 'payments',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'payment-detail',
                  type: BandType.detail,
                  height: 12,
                  elements: <ReportElement>[
                    _el('paymentAmount', expr: r'$F{amount}'),
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Schema B: ambiguous at a NESTED scope
//
// A single master-scope collection `orders`. Each order has two sibling
// sub-collections — `items` and `discounts` — both containing `amount`.
// resolveAggregatePath(orderChildFields, 'amount') returns Ambiguous.
// The `orders` NestedScope has a footer with SUM($F{amount}).
// ---------------------------------------------------------------------------

const List<FieldDef> _ambiguousNestedSchema = <FieldDef>[
  FieldDef('orderId', type: JetFieldType.string),
  FieldDef('items', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('amount', type: JetFieldType.double),
  ]),
  FieldDef('discounts', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('amount', type: JetFieldType.double),
  ]),
];

List<Map<String, Object?>> _ambiguousNestedRows() => <Map<String, Object?>>[
      <String, Object?>{
        'orders': <Map<String, Object?>>[
          <String, Object?>{
            'orderId': 'O1',
            'items': <Map<String, Object?>>[
              <String, Object?>{'amount': 10.0},
            ],
            'discounts': <Map<String, Object?>>[
              <String, Object?>{'amount': 2.0},
            ],
          },
        ],
      },
    ];

ReportDefinition _makeAmbiguousNestedFooterDef() => ReportDefinition(
      name: 'ambiguousNestedFooterTest',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'orders',
              collectionField: 'orders',
              footer: Band(
                id: 'orders-footer',
                type: BandType.groupFooter,
                height: 12,
                elements: <ReportElement>[
                  _el('orderTotal', expr: r'SUM($F{amount})'),
                ],
              ),
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
                  id: 'items',
                  collectionField: 'items',
                  children: <ScopeNode>[
                    BandNode(Band(
                      id: 'item-detail',
                      type: BandType.detail,
                      height: 12,
                      elements: <ReportElement>[
                        _el('itemAmount', expr: r'$F{amount}'),
                      ],
                    )),
                  ],
                )),
                NestedScope(DetailScope(
                  id: 'discounts',
                  collectionField: 'discounts',
                  children: <ScopeNode>[
                    BandNode(Band(
                      id: 'discount-detail',
                      type: BandType.detail,
                      height: 12,
                      elements: <ReportElement>[
                        _el('discountAmount', expr: r'$F{amount}'),
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

// ---------------------------------------------------------------------------
// Schema C: unambiguous master-scope — used for COUNT and AVG coverage tests.
//
// Root has a single collection `lines` containing `lineTotal`. No ambiguity.
// Structure mirrors descendant_summary_fill_test.dart so these tests remain
// focused on the aggregate function under test rather than fixture variety.
// ---------------------------------------------------------------------------

const List<FieldDef> _unambiguousSchema = <FieldDef>[
  FieldDef('customerId', type: JetFieldType.string),
  FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('lineTotal', type: JetFieldType.double),
  ]),
];

/// Two-customer fixture:
///   C1: lines [10, 20, 30] — 3 lines, sum = 60, avg = 20
///   C2: lines [100]        — 1 line, sum = 100, avg = 100
/// Grand totals: COUNT = 4, AVG = 160/4 = 40
List<Map<String, Object?>> _unambiguousRows() => <Map<String, Object?>>[
      <String, Object?>{
        'customerId': 'C1',
        'lines': <Map<String, Object?>>[
          <String, Object?>{'lineTotal': 10.0},
          <String, Object?>{'lineTotal': 20.0},
          <String, Object?>{'lineTotal': 30.0},
        ],
      },
      <String, Object?>{
        'customerId': 'C2',
        'lines': <Map<String, Object?>>[
          <String, Object?>{'lineTotal': 100.0},
        ],
      },
    ];

ReportDefinition _makeCountSummaryDef() => ReportDefinition(
      name: 'countSummaryTest',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 12,
          elements: <ReportElement>[
            _el('lineCount', expr: r'COUNT($F{lineTotal})'),
          ],
        ),
        root: DetailScope(
          id: 'root',
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
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

ReportDefinition _makeGroupAvgDef() => ReportDefinition(
      name: 'groupAvgTest',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'customer',
              name: 'customer',
              key: r'$F{customerId}',
              footer: Band(
                id: 'customer-footer',
                type: BandType.groupFooter,
                height: 12,
                elements: <ReportElement>[
                  _el('customerAvg', expr: r'AVG($F{lineTotal})'),
                ],
              ),
            ),
          ],
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
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _textOf(FilledBand band, String elementId) =>
    (band.elements.firstWhere((ReportElement e) => e.id == elementId)
            as TextElement)
        .text;

void main() {
  // -------------------------------------------------------------------------
  // FR-010 ambiguous-operand fallback tests
  // -------------------------------------------------------------------------

  group('ambiguous operand renders fallback token, never a number', () {
    test(
        'SUM over ambiguous operand at summary renders #ERROR '
        '(amount exists in both salesLines and payments)', () {
      final FillResult res = ReportFiller().fillDefinition(
        _makeAmbiguousSummaryDef(),
        JetInMemoryDataSource(_ambiguousRootRows(), fields: _ambiguousRootSchema),
      );

      // The summary is always the last band in the report.
      final FilledBand summary = res.report.bands.last;
      expect(summary.type, BandType.summary);
      expect(_textOf(summary, 'grandTotal'), '#ERROR',
          reason:
              'amount is ambiguous (salesLines vs payments) → fallback token');
    });

    test(
        'SUM over ambiguous operand at group footer renders #ERROR '
        '(amount exists in both salesLines and payments)', () {
      final FillResult res = ReportFiller().fillDefinition(
        _makeAmbiguousSummaryDef(),
        JetInMemoryDataSource(_ambiguousRootRows(), fields: _ambiguousRootSchema),
      );

      final List<FilledBand> footers = res.report.bands
          .where((FilledBand b) => b.type == BandType.groupFooter)
          .toList();

      // Two customers → two group footers.
      expect(footers, hasLength(2),
          reason: 'one footer per customer: C1 and C2');

      // Both footers should show the fallback, not a number.
      for (final FilledBand footer in footers) {
        expect(_textOf(footer, 'customerTotal'), '#ERROR',
            reason:
                'amount is ambiguous at master scope → footer fallback token');
      }
    });

    test(
        'SUM over ambiguous operand at nested-scope footer renders #ERROR '
        '(amount exists in both items and discounts under orders)', () {
      // Provide the orders schema for childRowsOf projection, but the root
      // schema just has a single 'orders' collection entry.
      final FillResult res = ReportFiller().fillDefinition(
        _makeAmbiguousNestedFooterDef(),
        JetInMemoryDataSource(
          _ambiguousNestedRows(),
          fields: <FieldDef>[
            FieldDef('orders',
                type: JetFieldType.collection,
                fields: _ambiguousNestedSchema),
          ],
        ),
      );

      final List<FilledBand> footers = res.report.bands
          .where((FilledBand b) => b.type == BandType.groupFooter)
          .toList();

      // One master row with one order → one footer emitted.
      expect(footers, hasLength(1),
          reason: 'one footer per order-iteration');

      expect(_textOf(footers.first, 'orderTotal'), '#ERROR',
          reason:
              'amount is ambiguous at orders scope (items vs discounts) → '
              'fallback token');
    });
  });

  // -------------------------------------------------------------------------
  // Additional coverage: COUNT at summary + group-footer AVG
  // -------------------------------------------------------------------------

  group('COUNT and AVG descendant aggregates', () {
    test(
        'COUNT descendant aggregate at summary renders flat leaf count '
        '(C1: 3 lines, C2: 1 line → total COUNT = 4)', () {
      final FillResult res = ReportFiller().fillDefinition(
        _makeCountSummaryDef(),
        JetInMemoryDataSource(_unambiguousRows(), fields: _unambiguousSchema),
      );

      final FilledBand summary = res.report.bands.last;
      expect(summary.type, BandType.summary);
      // COUNT accumulates as a double (consistent with other aggregate types).
      expect(_textOf(summary, 'lineCount'), '4.0',
          reason: 'flat COUNT over all 4 leaf lines = 4');

      expect(res.diagnostics.hasErrors, isFalse,
          reason: 'no errors expected: ${res.diagnostics.entries}');
    });

    test(
        'AVG descendant aggregate at group footer renders per-group flat average '
        '(C1: avg(10,20,30)=20; C2: avg(100)=100) — exercises the reset-of-count path',
        () {
      final FillResult res = ReportFiller().fillDefinition(
        _makeGroupAvgDef(),
        JetInMemoryDataSource(_unambiguousRows(), fields: _unambiguousSchema),
      );

      final List<FilledBand> footers = res.report.bands
          .where((FilledBand b) => b.type == BandType.groupFooter)
          .toList();

      // Two customers → two group footers.
      expect(footers, hasLength(2),
          reason: 'one footer per customer');

      // C1: AVG(10, 20, 30) = 60/3 = 20.0
      expect(_textOf(footers[0], 'customerAvg'), startsWith('20'),
          reason: 'C1 average = 20.0');
      // C2: AVG(100) = 100.0
      expect(_textOf(footers[1], 'customerAvg'), startsWith('100'),
          reason: 'C2 average = 100.0');

      expect(res.diagnostics.hasErrors, isFalse,
          reason: 'no errors expected: ${res.diagnostics.entries}');
    });
  });
}
