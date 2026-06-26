/// The playground's invoice sample (009): a data-source **structure** and a
/// matching bound **template**, built entirely through the library's public API
/// (`package:jet_print/jet_print.dart`) — the demo is an external consumer.
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// The invoice data structure: master fields plus a nested `lines` collection
/// (master/detail). Attach it to [JetReportDesigner] via `dataSchema:`.
///
/// Monetary fields model a real invoice's running tally: `total` is the
/// **subtotal** (the sum of the line totals — kept so the existing
/// "total equals its line-total sum" invariant still holds), then a `discount`
/// is taken off and `tax` and `shipping` add on top, so `grandTotal` is the
/// amount actually due. Because `discount` is stored **negative** (a deduction)
/// the identity stays a plain sum: `grandTotal == total + tax + shipping +
/// discount`. `taxLabel` / `discountLabel` are the human-readable rate captions
/// (e.g. `VAT 19%`, `Discount 10%`) so the layout never has to format a
/// percentage itself. `invoiceDescription` is the free-text summary shown below
/// the totals.
const JetDataSchema invoiceSchema = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef('billingAddress', type: JetFieldType.string),
    FieldDef('date', type: JetFieldType.dateTime),
    FieldDef('total', type: JetFieldType.double),
    FieldDef('discountLabel', type: JetFieldType.string),
    FieldDef('discount', type: JetFieldType.double),
    FieldDef('taxLabel', type: JetFieldType.string),
    FieldDef('tax', type: JetFieldType.double),
    FieldDef('shipping', type: JetFieldType.double),
    FieldDef('grandTotal', type: JetFieldType.double),
    FieldDef('paymentTerms', type: JetFieldType.string),
    FieldDef('shippingMethod', type: JetFieldType.string),
    FieldDef('notes', type: JetFieldType.string),
    FieldDef('invoiceDescription', type: JetFieldType.string),
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
);

/// Muted caption grey (section labels, page number, currency note).
const JetColor _grey = JetColor(0xFF888888);

/// Secondary body grey (date, address, description).
const JetColor _muted = JetColor(0xFF555555);

/// The playground accent blue — shared with the List demo — used for the
/// invoice's accent stripes (title bar, table rule, total rule, section ticks).
const JetColor _accent = JetColor(0xFF2F5C8A);

/// The content width the bands span, in points (matches the element columns).
const double _contentWidth = 540;

/// The **same invoice, authored in the reified band model** (spec 024) instead
/// of the flat [ReportTemplate] above — built entirely through the public API.
///
/// This is what the new architecture looks like end to end: roles are *stated
/// structurally*, not inferred from `type` + group-name + position.
///
/// * [PageFurniture] holds the record-blind page chrome — just the
///   [PageFurniture.pageFooter] `Page N of M`. There is no page header: each
///   invoice starts a new page and already carries its own big `INVOICE`
///   heading, so a running title would only repeat it.
/// * [ReportBody.root] is the master [DetailScope]. Its one [GroupLevel]
///   (`invoice`, keyed on `$F{invoiceNo}`) **owns** its header/footer bands and
///   its pagination flags ([GroupLevel.keepTogether] / [GroupLevel.startNewPage])
///   directly — the single home that fixes the old "same flag on both header and
///   footer band" smell.
/// * The line items are a nested [DetailScope] (`collectionField: 'lines'`)
///   holding one per-row [BandNode] — master/detail expressed as a tree.
///
/// Rendered through [JetReportEngine.renderDefinition] it is byte-identical to
/// rendering [invoiceSampleTemplate] (the native engine consumes the tree).
ReportDefinition invoiceSampleDefinition() => const ReportDefinition(
      name: 'Invoice',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
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
                  fontSize: 9, color: _grey, align: JetTextAlign.right),
              expression:
                  r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'invoice',
              name: 'invoice',
              key: r'$F{invoiceNo}',
              keepTogether: true,
              startNewPage: true,
              header: Band(
                id: 'invoiceHeader',
                type: BandType.groupHeader,
                height: 134,
                elements: <ReportElement>[
                  TextElement(
                    id: 'heading',
                    bounds: JetRect(x: 0, y: 0, width: 200, height: 28),
                    text: 'INVOICE',
                    style:
                        JetTextStyle(fontSize: 22, weight: JetFontWeight.bold),
                  ),
                  // A short accent bar underlines the INVOICE heading.
                  ShapeElement(
                    id: 'titleAccent',
                    bounds: JetRect(x: 0, y: 32, width: 150, height: 3),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _accent),
                  ),
                  // A full-width accent rule sets the column headers off from
                  // the line items below.
                  ShapeElement(
                    id: 'tableHeaderRule',
                    bounds: JetRect(
                        x: 0, y: 132, width: _contentWidth, height: 1.5),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _accent),
                  ),
                  TextElement(
                    id: 'invoiceNo',
                    bounds: JetRect(x: 340, y: 4, width: 200, height: 18),
                    text: 'invoiceNo',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'$F{invoiceNo}',
                  ),
                  TextElement(
                    id: 'date',
                    bounds: JetRect(x: 340, y: 26, width: 200, height: 16),
                    text: 'date',
                    style:
                        JetTextStyle(align: JetTextAlign.right, color: _muted),
                    expression: r'"Date: " + $F{date}',
                  ),
                  TextElement(
                    id: 'billToLabel',
                    bounds: JetRect(x: 0, y: 40, width: 200, height: 14),
                    text: 'BILL TO',
                    style: JetTextStyle(
                        fontSize: 9, weight: JetFontWeight.bold, color: _grey),
                  ),
                  TextElement(
                    id: 'customerName',
                    bounds: JetRect(x: 0, y: 54, width: 320, height: 18),
                    text: 'customerName',
                    style: JetTextStyle(weight: JetFontWeight.bold),
                    expression: r'$F{customerName}',
                  ),
                  TextElement(
                    id: 'billingAddress',
                    bounds: JetRect(x: 0, y: 72, width: 320, height: 44),
                    text: 'billingAddress',
                    style: JetTextStyle(fontSize: 10, color: _muted),
                    expression: r'$F{billingAddress}',
                  ),
                  TextElement(
                    id: 'colDescription',
                    bounds: JetRect(x: 0, y: 116, width: 260, height: 16),
                    text: 'Description',
                    style: JetTextStyle(weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colQty',
                    bounds: JetRect(x: 270, y: 116, width: 50, height: 16),
                    text: 'Qty',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colUnitPrice',
                    bounds: JetRect(x: 330, y: 116, width: 90, height: 16),
                    text: 'Unit Price',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colAmount',
                    bounds: JetRect(x: 430, y: 116, width: 110, height: 16),
                    text: 'Amount',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                ],
              ),
              footer: Band(
                id: 'invoiceFooter',
                type: BandType.groupFooter,
                height: 212,
                elements: <ReportElement>[
                  // Right column — the running money tally: subtotal less the
                  // discount, plus tax and shipping, equals the Grand Total
                  // (the only emphasized line). `discount` is stored negative,
                  // so it renders with its own minus sign.
                  TextElement(
                    id: 'subtotalLabel',
                    bounds: JetRect(x: 300, y: 6, width: 120, height: 16),
                    text: 'Subtotal',
                    style: JetTextStyle(align: JetTextAlign.right),
                  ),
                  TextElement(
                    id: 'subtotal',
                    bounds: JetRect(x: 430, y: 6, width: 110, height: 16),
                    text: 'total',
                    style: JetTextStyle(align: JetTextAlign.right),
                    expression: r'$F{total}',
                    format: '#,##0.00',
                  ),
                  TextElement(
                    id: 'discountLabel',
                    bounds: JetRect(x: 240, y: 24, width: 180, height: 16),
                    text: 'discountLabel',
                    style: JetTextStyle(align: JetTextAlign.right),
                    expression: r'$F{discountLabel}',
                  ),
                  TextElement(
                    id: 'discount',
                    bounds: JetRect(x: 430, y: 24, width: 110, height: 16),
                    text: 'discount',
                    style: JetTextStyle(align: JetTextAlign.right),
                    expression: r'$F{discount}',
                    format: '#,##0.00',
                  ),
                  TextElement(
                    id: 'taxLabel',
                    bounds: JetRect(x: 240, y: 42, width: 180, height: 16),
                    text: 'taxLabel',
                    style: JetTextStyle(align: JetTextAlign.right),
                    expression: r'$F{taxLabel}',
                  ),
                  TextElement(
                    id: 'tax',
                    bounds: JetRect(x: 430, y: 42, width: 110, height: 16),
                    text: 'tax',
                    style: JetTextStyle(align: JetTextAlign.right),
                    expression: r'$F{tax}',
                    format: '#,##0.00',
                  ),
                  TextElement(
                    id: 'shippingLabel',
                    bounds: JetRect(x: 300, y: 60, width: 120, height: 16),
                    text: 'Shipping',
                    style: JetTextStyle(align: JetTextAlign.right),
                  ),
                  TextElement(
                    id: 'shipping',
                    bounds: JetRect(x: 430, y: 60, width: 110, height: 16),
                    text: 'shipping',
                    style: JetTextStyle(align: JetTextAlign.right),
                    expression: r'$F{shipping}',
                    format: '#,##0.00',
                  ),
                  // An accent rule sets the Grand Total off from the tally above.
                  ShapeElement(
                    id: 'grandTotalRule',
                    bounds: JetRect(x: 280, y: 80, width: 260, height: 1.5),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _accent),
                  ),
                  TextElement(
                    id: 'grandTotalLabel',
                    bounds: JetRect(x: 280, y: 84, width: 140, height: 20),
                    text: 'Grand Total',
                    style: JetTextStyle(
                        fontSize: 12,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'grandTotal',
                    bounds: JetRect(x: 430, y: 84, width: 110, height: 20),
                    text: 'grandTotal',
                    style: JetTextStyle(
                        fontSize: 12,
                        align: JetTextAlign.right,
                        weight: JetFontWeight.bold),
                    expression: r'$F{grandTotal}',
                    format: '#,##0.00',
                  ),
                  // Left column — payment and shipping terms, each section
                  // marked by a thin accent tick in the left margin.
                  ShapeElement(
                    id: 'paymentTermsTick',
                    bounds: JetRect(x: 0, y: 6, width: 3, height: 12),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _accent),
                  ),
                  TextElement(
                    id: 'paymentTermsLabel',
                    bounds: JetRect(x: 10, y: 6, width: 190, height: 14),
                    text: 'PAYMENT TERMS',
                    style: JetTextStyle(
                        fontSize: 9, weight: JetFontWeight.bold, color: _grey),
                  ),
                  TextElement(
                    id: 'paymentTerms',
                    bounds: JetRect(x: 10, y: 20, width: 220, height: 16),
                    text: 'paymentTerms',
                    expression: r'$F{paymentTerms}',
                  ),
                  ShapeElement(
                    id: 'shippingTick',
                    bounds: JetRect(x: 0, y: 42, width: 3, height: 12),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _accent),
                  ),
                  TextElement(
                    id: 'shippingMethodLabel',
                    bounds: JetRect(x: 10, y: 42, width: 190, height: 14),
                    text: 'SHIPPING',
                    style: JetTextStyle(
                        fontSize: 9, weight: JetFontWeight.bold, color: _grey),
                  ),
                  TextElement(
                    id: 'shippingMethod',
                    bounds: JetRect(x: 10, y: 56, width: 220, height: 16),
                    text: 'shippingMethod',
                    expression: r'$F{shippingMethod}',
                  ),
                  // Invoice description — the free-text summary below the totals.
                  ShapeElement(
                    id: 'descriptionTick',
                    bounds: JetRect(x: 0, y: 118, width: 3, height: 12),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _accent),
                  ),
                  TextElement(
                    id: 'descriptionLabel',
                    bounds: JetRect(x: 10, y: 118, width: 190, height: 14),
                    text: 'DESCRIPTION',
                    style: JetTextStyle(
                        fontSize: 9, weight: JetFontWeight.bold, color: _grey),
                  ),
                  TextElement(
                    id: 'invoiceDescription',
                    bounds: JetRect(x: 10, y: 132, width: 530, height: 44),
                    text: 'invoiceDescription',
                    style: JetTextStyle(fontSize: 10, color: _muted),
                    expression: r'$F{invoiceDescription}',
                  ),
                  // Full-width footer note + currency caption.
                  TextElement(
                    id: 'notes',
                    bounds: JetRect(x: 0, y: 186, width: 330, height: 18),
                    text: 'notes',
                    style: JetTextStyle(fontSize: 9, color: _grey),
                    expression: r'$F{notes}',
                  ),
                  TextElement(
                    id: 'currencyNote',
                    bounds: JetRect(x: 340, y: 188, width: 200, height: 12),
                    text: 'All amounts in EUR',
                    style: JetTextStyle(
                        fontSize: 9, align: JetTextAlign.right, color: _grey),
                  ),
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
                  id: 'lineRow',
                  type: BandType.detail,
                  height: 22,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'lineDescription',
                      bounds: JetRect(x: 0, y: 2, width: 260, height: 16),
                      text: 'description',
                      expression: r'$F{description}',
                    ),
                    TextElement(
                      id: 'lineQty',
                      bounds: JetRect(x: 270, y: 2, width: 50, height: 16),
                      text: 'qty',
                      style: JetTextStyle(align: JetTextAlign.right),
                      expression: r'$F{qty}',
                      format: '#,##0',
                    ),
                    TextElement(
                      id: 'lineUnitPrice',
                      bounds: JetRect(x: 330, y: 2, width: 90, height: 16),
                      text: 'unitPrice',
                      style: JetTextStyle(align: JetTextAlign.right),
                      expression: r'$F{unitPrice}',
                      format: '#,##0.00',
                    ),
                    TextElement(
                      id: 'lineTotal',
                      bounds: JetRect(x: 430, y: 2, width: 110, height: 16),
                      text: 'lineTotal',
                      style: JetTextStyle(align: JetTextAlign.right),
                      expression: r'$F{lineTotal}',
                      format: '#,##0.00',
                    ),
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

/// A deliberately **blank** report over the *same* invoice data (attach
/// [invoiceSchema] via `dataSchema:`): the emptiest tree in the reified band
/// model — a bare root [DetailScope] with **no bands**, no page furniture, no
/// groups, no elements. The user adds the first band themselves via the
/// designer's "Add band" affordance.
///
/// It exists so the playground has a clean canvas for exercising the designer
/// by hand — adding bands, dropping elements, adding groups/lists, binding
/// fields — starting from nothing rather than from the fully-authored
/// [invoiceSampleDefinition]. Because it shares the invoice schema and data
/// source, any field the invoice binds is available to bind here too.
ReportDefinition emptyDesignDefinition() => const ReportDefinition(
      name: 'Empty',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root'),
      ),
    );
