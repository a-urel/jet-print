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
/// roll-up sums). Order totals, customer totals, and the grand total are
/// **not** data fields — they are computed live as inline multi-level
/// aggregates (spec 033): each footer element authors `SUM($F{lineTotal})`
/// directly, and the engine descends the [orders, lines] path at fill time
/// to fold over all descendant leaf rows. No `ScopeTotal` declarations are
/// needed; the whole Customer ▸ Order ▸ Line chain is live with a single
/// authoring expression at each level.
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

/// Muted secondary text — codes and captions.
const JetColor _grey = JetColor(0xFF888888);

/// Soft fill behind each customer header — the strongest group cue.
const JetColor _headerFill = JetColor(0xFFEDF1F6);

/// Accent rule along the bottom of the customer header.
const JetColor _accent = JetColor(0xFF2F5C8A);

/// Light tint behind each order's number/date line.
const JetColor _orderFill = JetColor(0xFFF4F6F9);

/// Hairline under the per-order column titles.
const JetColor _hair = JetColor(0xFFD3D8DF);

/// Dark rule that closes a total (customer total and grand total).
const JetColor _rule = JetColor(0xFF333333);

/// The content width all bands span, in points (matches the element columns).
const double _contentWidth = 540;

/// The nested-list report authored in the reified band model (spec 024).
///
/// Shape, top to bottom:
/// * [PageFurniture] holds the record-blind chrome (a `Customers` running title
///   and a `Page N of M` footer).
/// * [ReportBody.root] is the master [DetailScope] iterating customers. The
///   **customer** is a first-class [GroupLevel] (keyed on `$F{customerCode}`)
///   so it can own a header (name/code) *and* a footer showing the live
///   customer total — the supported way to wrap a nested list in
///   header+footer chrome, mirroring the invoice's per-invoice group.
/// * Under it, `orders` is a [NestedScope]; each order emits one per-row
///   `detail` band (number · date · the line column titles) followed by the
///   `lines` [NestedScope] — the list within the list.
///
/// The whole total chain is **live** via inline multi-level aggregates (spec
/// 033) — no figure above `lineTotal` is data, and no [ScopeTotal]
/// declarations are needed:
/// * the `lines` scope footer folds its own rows with `SUM($F{lineTotal})`
///   (same-scope fold — spec 029 path), giving the per-order total;
/// * the customer group footer uses the identical expression
///   `SUM($F{lineTotal})`, and the engine descends [orders, lines] to fold
///   all descendant leaf rows within that customer (spec 033 path);
/// * [ReportBody.summary] does the same descent over all customers, authoring
///   the grand total as `SUM($F{lineTotal})` (spec 033 path).
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
              style: JetTextStyle(fontSize: 9, color: _grey),
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
                  color: _grey,
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
            // Mirrors the customer-total rule to close the whole report.
            ShapeElement(
              id: 'grandTotalRule',
              bounds: JetRect(x: 300, y: 4, width: 240, height: 1),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _rule),
            ),
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
              expression: r'SUM($F{lineTotal})',
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
                  // Shaded section band + accent rule, drawn first so the
                  // name/code text paints over them — the strongest group cue.
                  ShapeElement(
                    id: 'customerHeaderBg',
                    bounds: JetRect(
                        x: 0, y: 0, width: _contentWidth, height: 30),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _headerFill),
                  ),
                  ShapeElement(
                    id: 'customerHeaderRule',
                    bounds: JetRect(
                        x: 0, y: 28, width: _contentWidth, height: 2),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _accent),
                  ),
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
                        align: JetTextAlign.right, color: _grey),
                    expression: r'$F{customerCode}',
                  ),
                ],
              ),
              footer: Band(
                id: 'customerFooter',
                type: BandType.groupFooter,
                height: 26,
                elements: <ReportElement>[
                  // A rule above the total closes the customer section.
                  ShapeElement(
                    id: 'customerTotalRule',
                    bounds: JetRect(x: 300, y: 1, width: 240, height: 1),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _rule),
                  ),
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
                    expression: r'SUM($F{lineTotal})',
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
              // No ScopeTotal: the inline SUM($F{lineTotal}) at the customer
              // footer + summary descend [orders, lines] at fill time (spec 033).

              children: <ScopeNode>[
                BandNode(Band(
                  id: 'orderRow',
                  type: BandType.detail,
                  height: 40,
                  elements: <ReportElement>[
                    // Light tint behind the order number/date line marks the
                    // start of a nested order group (drawn first, behind text).
                    ShapeElement(
                      id: 'orderRowBg',
                      bounds: JetRect(
                          x: 0, y: 0, width: _contentWidth, height: 20),
                      kind: ShapeKind.rectangle,
                      style: JetBoxStyle(fill: _orderFill),
                    ),
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
                    // The per-order total lives on the `lines` scope as a
                    // published total `orderTotal = SUM($F{lineTotal})` (spec 030,
                    // B2), displayed in the lines footer and rolled up into the
                    // customer total; the order row itself shows no total.
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
                    // Hairline under the column titles separates them from the
                    // line items below.
                    ShapeElement(
                      id: 'colRule',
                      bounds: JetRect(x: 24, y: 37, width: 516, height: 1),
                      kind: ShapeKind.rectangle,
                      style: JetBoxStyle(fill: _hair),
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
                  // No ScopeTotal: the footer folds the same-scope child rows
                  // inline (spec 029 path). No published field needed.
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
                            color: _grey),
                      ),
                      TextElement(
                        id: 'orderTotalFooter',
                        bounds: JetRect(x: 430, y: 1, width: 110, height: 16),
                        text: 'orderTotal',
                        style: JetTextStyle(
                            align: JetTextAlign.right,
                            weight: JetFontWeight.bold),
                        // Same-scope fold over the order's lines (spec 029).
                        expression: r'SUM($F{lineTotal})',
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
