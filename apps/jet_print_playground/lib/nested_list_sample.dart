/// The playground's nested-list sample: a three-level master/detail report —
/// **Customer ▸ Order ▸ Line** — authored entirely through the library's public
/// API (`package:jet_print/jet_print.dart`), the way an external consumer would.
///
/// Where the invoice sample nests one collection (`lines`) under a grouped
/// master, this one nests *two* (`orders`, then `lines` inside each order) to
/// show off the reified band model's arbitrary-depth nesting (spec 024):
/// `DetailScope.children` is an ordered list of [ScopeNode]s, and a
/// [NestedScope] simply wraps another [DetailScope] — so a list inside a list
/// is just recursion.
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// The customers data structure: master fields plus a nested `orders`
/// collection, each order carrying its own nested `lines` collection
/// (master/detail/detail). Attach it via `dataSchema:`.
///
/// The only stored money figure is `lineTotal` (the real per-line data the
/// roll-up sums). `orderTotal` and `customerTotal` are **not** data fields —
/// they are computed live as published scope totals (spec 030): the `lines`
/// scope publishes `orderTotal = SUM($F{lineTotal})` onto each order row, the
/// `orders` scope rolls those up into `customerTotal = SUM($F{orderTotal})` on
/// each customer row, and the summary sums those into the grand total. The
/// whole Customer ▸ Order ▸ Line chain is live; nothing is precomputed.
const JetDataSchema customersSchema = JetDataSchema(
  name: 'Customers',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef('customerCode', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('orderNo', type: JetFieldType.string),
        FieldDef('date', type: JetFieldType.dateTime),
        FieldDef(
          'lines',
          type: JetFieldType.collection,
          fields: <FieldDef>[
            FieldDef('description', type: JetFieldType.string),
            FieldDef('qty', type: JetFieldType.integer),
            FieldDef('unitPrice', type: JetFieldType.double),
            FieldDef('lineTotal', type: JetFieldType.double),
          ],
        ),
      ],
    ),
  ],
);

/// The nested-list report authored in the reified band model (spec 024).
///
/// Shape, top to bottom:
/// * [PageFurniture] holds the record-blind chrome (a `Customers` running title
///   and a `Page N of M` footer).
/// * [ReportBody.root] is the master [DetailScope] iterating customers. The
///   **customer** is a first-class [GroupLevel] (keyed on `$F{customerCode}`)
///   so it can own a header (name/code) *and* a footer showing the live
///   `$F{customerTotal}` — the supported way to wrap a nested list in
///   header+footer chrome, mirroring the invoice's per-invoice group.
/// * Under it, `orders` is a [NestedScope]; each order emits one per-row
///   `detail` band (number · date · the line column titles) followed by the
///   `lines` [NestedScope] — the list within the list.
///
/// The whole total chain is **live** via published scope totals (spec 030),
/// computed bottom-up — no figure above `lineTotal` is data:
/// * the `lines` scope publishes `orderTotal = SUM($F{lineTotal})` (its
///   [DetailScope.totals]) onto each order row, and its `footer` band simply
///   displays that published field (`$F{orderTotal}`) — one computation reused;
/// * the `orders` scope rolls those up, publishing
///   `customerTotal = SUM($F{orderTotal})` onto each customer row, which the
///   customer group footer displays as `$F{customerTotal}`;
/// * [ReportBody.summary] sums those into the grand total, authored **inline**
///   in the summary element as `{SUM([customerTotal])}` (stored
///   `SUM($F{customerTotal})`) over the now-live injected field.
ReportDefinition nestedListsDefinition() => const ReportDefinition(
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
              // Rolls the published per-order totals up one more level (spec
              // 030): `customerTotal = SUM($F{orderTotal})` is injected onto
              // each customer row, where the customer group footer displays it.
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
                    // The per-order total moved to the `lines`-scope footer
                    // (a live SUM([lineTotal]) aggregate, spec 029); the order
                    // row no longer shows the precomputed `$F{orderTotal}`.
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
                  // The `lines` scope PUBLISHES the per-order total as a named
                  // roll-up (spec 030): `orderTotal = SUM($F{lineTotal})` is
                  // injected onto each order row, so the footer below — and the
                  // enclosing `orders` scope — reference one computed value.
                  totals: <ScopeTotal>[
                    ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
                  ],
                  // The footer just DISPLAYS the published field ($F{orderTotal})
                  // rather than recomputing the aggregate inline.
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
