// SC-001 parity proof (spec 033): the now-inline-authored shipped sample
// (`nestedListsDefinition()`) renders byte-identical totals to the
// published-total design (`_publishedTotalDefinition()`) when both are filled
// over the same declared-schema source.
//
// After the spec-033 migration, `nestedListsDefinition()` IS the inline
// variant.  This test is repurposed to keep proving SC-001 equivalence by
// comparing it against a hand-kept published-total reference built in-test —
// the same role the original parity test served, with the sides swapped.
//
// WHY declared schema: source-level inference does NOT type nested List<Map> as
// collections (a known deferred gap), so the inline sample's root-scope descend
// paths ([orders, lines]) need `ds.fields` to carry the typed schema.
// The published-total version works either way; rendering both over a
// declared-schema source is a fair, working comparison.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/nested_list_sample.dart';
import 'package:jet_print_playground/rendered_nested_list_example.dart';

void main() {
  group('SC-001 parity: inline (shipped sample) vs published-total', () {
    test('validate(nestedListsDefinition()) is empty (SC-003)', () {
      expect(validate(nestedListsDefinition()), isEmpty);
    });

    test('inline sample render has no errors in diagnostics', () {
      final RenderedReport report = const JetReportEngine()
          .renderDefinition(nestedListsDefinition(), _declaredSource());
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
        reason: 'inline multi-level sample + declared-schema source '
            'renders cleanly (no #ERROR / unresolved)',
      );
    });

    test('inline sample renders byte-identical to published-total (SC-001)',
        () {
      final RenderedReport inlineReport = const JetReportEngine()
          .renderDefinition(nestedListsDefinition(), _declaredSource());
      final RenderedReport publishedReport = const JetReportEngine()
          .renderDefinition(_publishedTotalDefinition(), _declaredSource());

      expect(
        _textRuns(inlineReport),
        _textRuns(publishedReport),
        reason: 'inline SUM(\$F{lineTotal}) at every footer level renders '
            'byte-identical totals to the published-total chain (SC-001)',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers (top-level)
// ---------------------------------------------------------------------------

/// Declared-schema source — REQUIRED so the inline variant's root-scope
/// descend paths ([orders, lines]) resolve. Both renders use the same source
/// factory so the comparison is apples-to-apples.
JetDataSource _declaredSource() =>
    JetInMemoryDataSource(kSampleCustomers, fields: customersSchema.fields);

// ---------------------------------------------------------------------------
// Published-total reference variant (the legacy design, kept for SC-001)
// ---------------------------------------------------------------------------

/// The published-total design that predates the spec-033 migration — kept
/// in-test as the SC-001 reference.  Identical structure to
/// [nestedListsDefinition], but total expressions use the published-field
/// pattern (`$F{orderTotal}` / `$F{customerTotal}`) and both scopes carry
/// their [ScopeTotal] declarations.
///
/// This is the counterpart to what [nestedListsDefinition] used to look like
/// before the migration; keeping it here lets the parity test prove that the
/// now-inline shipped sample renders byte-identical output (SC-001).
ReportDefinition _publishedTotalDefinition() => const ReportDefinition(
      name: 'Nested Lists',
      page: PageFormat.a4Portrait,
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
              // Sums the injected customerTotal field published by the orders scope.
              expression: r'SUM($F{customerTotal})',
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
                    // Displays the published field injected by the orders scope.
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
              // Publishes customerTotal = SUM($F{orderTotal}) onto each customer
              // row so the customer group footer can display it.
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
                  // Publishes orderTotal = SUM($F{lineTotal}) onto each order row
                  // so the footer and the enclosing orders scope can reference it.
                  totals: <ScopeTotal>[
                    ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
                  ],
                  // Displays the published field — one computation reused.
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
                        // Displays the published field (not an inline aggregate).
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

// ---------------------------------------------------------------------------
// Helpers (mirrored from nested_list_definition_test.dart)
// ---------------------------------------------------------------------------

/// Every rendered text run on every page of [report], in paint order —
/// the comparable shape used to prove two definitions render identically.
List<String> _textRuns(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          p.lines.map((TextLine l) => l.text).join(),
    ];
