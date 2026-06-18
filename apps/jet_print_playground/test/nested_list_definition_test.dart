// Confirms the nested-list sample (Customer ▸ Order ▸ Line) is authored as a
// genuinely nested tree in the reified band model (spec 024): two collection
// scopes deep, with per-record chrome expressed the supported way (a customer
// GroupLevel) so the definition is pristine under the library validator, and
// rendering it through the native renderDefinition path is clean — all through
// `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
// Implementation imports: the rendered display-list primitives aren't part of
// the public surface, so this equivalence proof reaches into them the same way
// the engine's own tests do (jet_report_engine_test.dart's `_allRuns`).
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/nested_list_sample.dart';
import 'package:jet_print_playground/rendered_nested_list_example.dart';

void main() {
  group('nested-list sample', () {
    test('is authored Customer ▸ Order ▸ Line, two nested scopes deep', () {
      final ReportDefinition def = nestedListsDefinition();

      // Page chrome lives in record-blind furniture.
      expect(def.furniture.pageHeader?.type, BandType.pageHeader);
      expect(def.furniture.pageFooter?.type, BandType.pageFooter);

      // The master scope iterates customers (a root scope carries no
      // collectionField).
      final DetailScope root = def.body.root;
      expect(root.collectionField, isNull);

      // The customer is a first-class group owning its header/footer chrome —
      // the supported home for per-record header+footer (cf. the invoice).
      expect(root.groups, hasLength(1));
      final GroupLevel customer = root.groups.single;
      expect(customer.key, r'$F{customerCode}');
      expect(customer.header?.type, BandType.groupHeader);
      expect(customer.footer?.type, BandType.groupFooter);

      // List #1: orders nested under the customer.
      expect(root.children, hasLength(1));
      final DetailScope orders = (root.children.single as NestedScope).scope;
      expect(orders.collectionField, 'orders');

      // Each order emits one per-order band (the reified per-row `detail` slot)
      // followed by its lines.
      expect(orders.children.first, isA<BandNode>());
      expect((orders.children.first as BandNode).band.type, BandType.detail);

      // List #2: lines nested under each order — a list within a list.
      final DetailScope lines =
          orders.children.whereType<NestedScope>().single.scope;
      expect(lines.collectionField, 'lines');
      expect(lines.children.single, isA<BandNode>());
      expect((lines.children.single as BandNode).band.type, BandType.detail);
    });

    test(
        'every footer level is authored inline as SUM(\$F{lineTotal}) (spec 033)',
        () {
      final ReportDefinition def = nestedListsDefinition();
      final DetailScope root = def.body.root;

      // The `lines` scope footer folds its own rows inline — no ScopeTotal.
      final DetailScope lines = _findScope(root, 'lines');
      expect(lines.totals, isEmpty,
          reason: 'no ScopeTotal on lines scope: inline fold replaces it');
      expect(lines.footer, isNotNull);
      final TextElement orderTotalFooter = lines.footer!.elements
          .firstWhere((ReportElement e) => e.id == 'orderTotalFooter')
          as TextElement;
      expect(orderTotalFooter.expression, r'SUM($F{lineTotal})',
          reason: 'lines footer folds the same-scope lines inline (spec 029)');

      // The `orders` scope carries no ScopeTotal: the customer footer + summary
      // descend [orders, lines] via spec 033 inline folding.
      final DetailScope orders = _findScope(root, 'orders');
      expect(orders.totals, isEmpty,
          reason: 'no ScopeTotal on orders scope: inline fold replaces it');

      // The customer group footer element is authored inline as SUM($F{lineTotal}).
      final GroupLevel customer = root.groups.single;
      final TextElement customerTotal = customer.footer!.elements
          .firstWhere((ReportElement e) => e.id == 'customerTotal')
          as TextElement;
      expect(customerTotal.expression, r'SUM($F{lineTotal})',
          reason:
              'customer footer descends [orders, lines] inline (spec 033)');

      // The summary grand total is also inline — descends [orders, lines].
      final TextElement grand = def.body.summary!.elements
          .firstWhere((ReportElement e) => e.id == 'grandTotal') as TextElement;
      expect(grand.expression, r'SUM($F{lineTotal})',
          reason: 'grand total descends [orders, lines] inline (spec 033)');
    });

    test('rendered customer footer totals + grand total are live data sums',
        () {
      final RenderedReport report = renderNestedListsDefinition();

      // Expected per-customer total = sum over that customer's orders of
      // (sum of that order's line lineTotals), derived from the SAME data the
      // render fills, formatted exactly as the footer formats (`#,##0.00`).
      final List<String> expectedCustomerTotals = <String>[
        for (final Map<String, Object?> customer in kSampleCustomers)
          _formatTotal(_customerSum(customer)),
      ];
      final List<String> actualCustomerTotals =
          _runsForId(report, 'customerTotal');
      expect(actualCustomerTotals, expectedCustomerTotals,
          reason: 'each customer footer total equals the live roll-up of its '
              'orders’ line-sums (SC-001)');

      // The grand total = the overall sum across all customers.
      final double grand = kSampleCustomers.fold<double>(
          0, (double sum, Map<String, Object?> c) => sum + _customerSum(c));
      final List<String> actualGrand = _runsForId(report, 'grandTotal');
      expect(actualGrand, <String>[_formatTotal(grand)],
          reason: 'the grand total equals the overall live data sum (SC-002)');
    });

    test('rendered per-order footer totals equal the data line-sums', () {
      final RenderedReport report = renderNestedListsDefinition();

      // Expected: for each order in the sample data, the sum of its lines'
      // lineTotal, formatted exactly as the footer element formats it
      // (`#,##0.00`). Derived from the SAME source the render fills.
      final List<String> expected = <String>[
        for (final Map<String, Object?> customer in kSampleCustomers)
          for (final Map<String, Object?> order
              in (customer['orders']! as List<Object?>).cast())
            _formatTotal((order['lines']! as List<Object?>)
                .cast<Map<String, Object?>>()
                .fold<double>(
                    0, (sum, line) => sum + (line['lineTotal']! as num))),
      ];

      // Actual: the rendered runs of the live footer total element (id
      // 'orderTotalFooter' — distinct from the removed precomputed 'orderTotal'
      // data field so this proves the SUM([lineTotal]) footer, not the data
      // field), in paint order, one per order.
      final List<String> actual = _runsForId(report, 'orderTotalFooter');

      expect(actual, expected,
          reason:
              'each live lines-scope footer total equals the data line-sum');
    });

    test('the grand total is authored inline (no declared variable)', () {
      final ReportDefinition def = nestedListsDefinition();
      expect(def.variables, isEmpty,
          reason:
              'the aggregate is inline in the summary, not a declared variable');
      final TextElement el = def.body.summary!.elements
          .firstWhere((ReportElement e) => e.id == 'grandTotal') as TextElement;
      expect(el.expression, r'SUM($F{lineTotal})');
      // Surfaced once at the end, in the summary band.
      expect(def.body.summary?.type, BandType.summary);
    });

    test(
        'migrated inline sample renders identically to the legacy '
        'published-total design',
        () {
      final RenderedReport inlineReport = const JetReportEngine()
          .renderDefinition(nestedListsDefinition(), _sampleSource());
      final RenderedReport legacyReport = const JetReportEngine()
          .renderDefinition(_legacyGrandTotalDefinition(), _sampleSource());
      expect(_textRuns(inlineReport), _textRuns(legacyReport),
          reason:
              'inline SUM(\$F{lineTotal}) at every footer level renders '
              'byte-identical output to the legacy published-total chain '
              '(SC-001 equivalence — migration correctness proof)');
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(nestedListsDefinition()), isEmpty);
    });

    test('renderDefinition fills the nested customers/orders/lines cleanly',
        () {
      final RenderedReport report = renderNestedListsDefinition();
      expect(report.pageCount, greaterThan(0));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
        reason:
            'a fully-bound nested definition + matching data renders cleanly',
      );
    });
  });
}

/// The sample data the render test exercises — the same source
/// [renderNestedListsDefinition] fills (Customer ▸ Order ▸ Line).
JetDataSource _sampleSource() => customersDataSource();

/// Recursively finds the [DetailScope] with [id] within [root]'s nested-scope
/// tree (depth-first over [NestedScope] children). Throws if not found.
DetailScope _findScope(DetailScope root, String id) {
  if (root.id == id) return root;
  for (final ScopeNode node in root.children) {
    if (node is NestedScope) {
      final DetailScope? found = _tryFindScope(node.scope, id);
      if (found != null) return found;
    }
  }
  throw StateError('no scope with id "$id"');
}

DetailScope? _tryFindScope(DetailScope root, String id) {
  if (root.id == id) return root;
  for (final ScopeNode node in root.children) {
    if (node is NestedScope) {
      final DetailScope? found = _tryFindScope(node.scope, id);
      if (found != null) return found;
    }
  }
  return null;
}

/// The data-derived total for one [customer]: the sum, over each of its orders,
/// of that order's line `lineTotal`s — the live roll-up the published scope
/// totals must reproduce. The single source of truth for the value proof.
double _customerSum(Map<String, Object?> customer) =>
    (customer['orders']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .fold<double>(
          0,
          (double sum, Map<String, Object?> order) =>
              sum +
              (order['lines']! as List<Object?>)
                  .cast<Map<String, Object?>>()
                  .fold<double>(
                      0,
                      (double s, Map<String, Object?> l) =>
                          s + (l['lineTotal']! as num)),
        );

/// Formats a total exactly the way the footer element does: the engine applies
/// the numeric `format` `#,##0.00` via `intl`'s `NumberFormat` (see
/// `apply_jet_format.dart`), so the proof formats with the same
/// `NumberFormat('#,##0.00')` — self-healing for values ≥1000 where
/// `toStringAsFixed(2)` would diverge (no grouping separator).
String _formatTotal(double value) => NumberFormat('#,##0.00').format(value);

/// The rendered text runs of the element with [elementId], in paint order
/// across all pages — the live footer-total values, one per emitted footer.
List<String> _runsForId(RenderedReport report, String elementId) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          if (p.elementId == elementId)
            p.lines.map((TextLine l) => l.text).join(),
    ];

/// Every rendered text run on every page of [report], in paint order — the
/// comparable shape used to prove two definitions render identically. Mirrors
/// the engine suite's `_allRuns` (collecting ALL runs, unfiltered).
List<String> _textRuns(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          p.lines.map((TextLine l) => l.text).join(),
    ];

/// The grand total in the *pre-migration* (hand-declared) form: a report-scoped
/// `grandTotal` [ReportVariable] surfaced via `$V{grandTotal}` in the summary.
/// Everything else is identical to [nestedListsDefinition] so the equivalence
/// proof isolates the grand-total authoring (inline `SUM($F{customerTotal})`
/// vs. this declared variable).
ReportDefinition _legacyGrandTotalDefinition() => const ReportDefinition(
      name: 'Nested Lists',
      page: PageFormat.a4Portrait,
      variables: <ReportVariable>[
        ReportVariable(
          name: 'grandTotal',
          expression: r'$F{customerTotal}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.report,
        ),
      ],
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'runningTitle',
              bounds: JetRect(x: 0, y: 2, width: 300, height: 14),
              text: 'Customers',
              style: JetTextStyle(fontSize: 9, color: JetColor(0xFF888888)),
            ),
          ],
        ),
        pageFooter: Band(
          id: 'pageFooter',
          type: BandType.pageFooter,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'pageNumber',
              bounds: JetRect(x: 0, y: 2, width: 540, height: 14),
              text: 'Page',
              style: JetTextStyle(
                  fontSize: 9,
                  color: JetColor(0xFF888888),
                  align: JetTextAlign.right),
              expression:
                  r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ),
      body: ReportBody(
        summary: Band(
          id: 'summary',
          type: BandType.summary,
          height: 30,
          elements: <ReportElement>[
            TextElement(
              id: 'grandTotalLabel',
              bounds: JetRect(x: 300, y: 8, width: 120, height: 18),
              text: 'Grand total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'grandTotal',
              bounds: JetRect(x: 430, y: 8, width: 110, height: 18),
              text: 'grandTotal',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'$V{grandTotal}',
              format: '#,##0.00',
            ),
          ],
        ),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'customer',
              name: 'customer',
              key: r'$F{customerCode}',
              keepTogether: true,
              header: Band(
                id: 'customerHeader',
                type: BandType.groupHeader,
                height: 30,
                elements: <ReportElement>[
                  TextElement(
                    id: 'customerName',
                    bounds: JetRect(x: 0, y: 4, width: 320, height: 20),
                    text: 'customerName',
                    style:
                        JetTextStyle(fontSize: 14, weight: JetFontWeight.bold),
                    expression: r'$F{customerName}',
                  ),
                  TextElement(
                    id: 'customerCode',
                    bounds: JetRect(x: 360, y: 6, width: 180, height: 16),
                    text: 'customerCode',
                    style: JetTextStyle(
                        align: JetTextAlign.right, color: JetColor(0xFF888888)),
                    expression: r'$F{customerCode}',
                  ),
                ],
              ),
              footer: Band(
                id: 'customerFooter',
                type: BandType.groupFooter,
                height: 26,
                elements: <ReportElement>[
                  TextElement(
                    id: 'customerTotalLabel',
                    bounds: JetRect(x: 300, y: 4, width: 120, height: 18),
                    text: 'Customer total',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'customerTotal',
                    bounds: JetRect(x: 430, y: 4, width: 110, height: 18),
                    text: 'customerTotal',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'$F{customerTotal}',
                    format: '#,##0.00',
                  ),
                ],
              ),
            ),
          ],
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'orders',
              collectionField: 'orders',
              totals: <ScopeTotal>[
                ScopeTotal('customerTotal', r'SUM($F{orderTotal})'),
              ],
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'orderRow',
                  type: BandType.detail,
                  height: 40,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'orderNo',
                      bounds: JetRect(x: 12, y: 2, width: 180, height: 16),
                      text: 'orderNo',
                      style: JetTextStyle(weight: JetFontWeight.bold),
                      expression: r'$F{orderNo}',
                    ),
                    TextElement(
                      id: 'date',
                      bounds: JetRect(x: 196, y: 2, width: 130, height: 16),
                      text: 'date',
                      expression: r'$F{date}',
                    ),
                    TextElement(
                      id: 'colDescription',
                      bounds: JetRect(x: 24, y: 22, width: 236, height: 14),
                      text: 'Description',
                      style:
                          JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
                    ),
                    TextElement(
                      id: 'colQty',
                      bounds: JetRect(x: 270, y: 22, width: 50, height: 14),
                      text: 'Qty',
                      style: JetTextStyle(
                          fontSize: 9,
                          align: JetTextAlign.right,
                          weight: JetFontWeight.bold),
                    ),
                    TextElement(
                      id: 'colUnitPrice',
                      bounds: JetRect(x: 330, y: 22, width: 90, height: 14),
                      text: 'Unit Price',
                      style: JetTextStyle(
                          fontSize: 9,
                          align: JetTextAlign.right,
                          weight: JetFontWeight.bold),
                    ),
                    TextElement(
                      id: 'colAmount',
                      bounds: JetRect(x: 430, y: 22, width: 110, height: 14),
                      text: 'Amount',
                      style: JetTextStyle(
                          fontSize: 9,
                          align: JetTextAlign.right,
                          weight: JetFontWeight.bold),
                    ),
                  ],
                )),
                NestedScope(DetailScope(
                  id: 'lines',
                  collectionField: 'lines',
                  children: <ScopeNode>[
                    BandNode(Band(
                      id: 'lineRow',
                      type: BandType.detail,
                      height: 18,
                      elements: <ReportElement>[
                        TextElement(
                          id: 'lineDescription',
                          bounds: JetRect(x: 24, y: 1, width: 236, height: 16),
                          text: 'description',
                          expression: r'$F{description}',
                        ),
                        TextElement(
                          id: 'lineQty',
                          bounds: JetRect(x: 270, y: 1, width: 50, height: 16),
                          text: 'qty',
                          style: JetTextStyle(align: JetTextAlign.right),
                          expression: r'$F{qty}',
                        ),
                        TextElement(
                          id: 'lineUnitPrice',
                          bounds: JetRect(x: 330, y: 1, width: 90, height: 16),
                          text: 'unitPrice',
                          style: JetTextStyle(align: JetTextAlign.right),
                          expression: r'$F{unitPrice}',
                          format: '#,##0.00',
                        ),
                        TextElement(
                          id: 'lineTotal',
                          bounds: JetRect(x: 430, y: 1, width: 110, height: 16),
                          text: 'lineTotal',
                          style: JetTextStyle(align: JetTextAlign.right),
                          expression: r'$F{lineTotal}',
                          format: '#,##0.00',
                        ),
                      ],
                    )),
                  ],
                  // Same lines-scope totals + footer as the primary definition
                  // — must stay in sync (publishes orderTotal, footer displays
                  // the published field).
                  totals: <ScopeTotal>[
                    ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
                  ],
                  footer: Band(
                    id: 'linesFooter',
                    type: BandType.groupFooter,
                    height: 18,
                    elements: <ReportElement>[
                      TextElement(
                        id: 'orderTotalLabel2',
                        bounds: JetRect(x: 320, y: 1, width: 105, height: 16),
                        text: 'Order total',
                        style: JetTextStyle(
                            align: JetTextAlign.right,
                            color: JetColor(0xFF888888)),
                      ),
                      TextElement(
                        id: 'orderTotalFooter',
                        bounds: JetRect(x: 430, y: 1, width: 110, height: 16),
                        text: 'orderTotal',
                        style: JetTextStyle(
                            align: JetTextAlign.right,
                            weight: JetFontWeight.bold),
                        expression: r'$F{orderTotal}',
                        format: '#,##0.00',
                      ),
                    ],
                  ),
                )),
              ],
            )),
          ],
        ),
      ),
    );
