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
const JetDataSchema invoiceSchema = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef('date', type: JetFieldType.dateTime),
    FieldDef('total', type: JetFieldType.double),
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

/// The **same invoice, authored in the reified band model** (spec 024) instead
/// of the flat [ReportTemplate] above — built entirely through the public API.
///
/// This is what the new architecture looks like end to end: roles are *stated
/// structurally*, not inferred from `type` + group-name + position.
///
/// * [PageFurniture] holds the record-blind page chrome ([PageFurniture.pageHeader]
///   running title, [PageFurniture.pageFooter] `Page N of M`).
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
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'runningTitle',
              bounds: JetRect(x: 0, y: 2, width: 300, height: 14),
              text: 'Invoices',
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
                height: 80,
                elements: <ReportElement>[
                  TextElement(
                    id: 'heading',
                    bounds: JetRect(x: 0, y: 0, width: 200, height: 28),
                    text: 'INVOICE',
                    style:
                        JetTextStyle(fontSize: 22, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'invoiceNo',
                    bounds: JetRect(x: 360, y: 4, width: 180, height: 18),
                    text: 'invoiceNo',
                    style: JetTextStyle(align: JetTextAlign.right),
                    expression: r'$F{invoiceNo}',
                  ),
                  TextElement(
                    id: 'customerName',
                    bounds: JetRect(x: 0, y: 34, width: 300, height: 18),
                    text: 'customerName',
                    expression: r'$F{customerName}',
                  ),
                  TextElement(
                    id: 'date',
                    bounds: JetRect(x: 360, y: 34, width: 180, height: 18),
                    text: 'date',
                    style: JetTextStyle(align: JetTextAlign.right),
                    expression: r'$F{date}',
                  ),
                  TextElement(
                    id: 'colDescription',
                    bounds: JetRect(x: 0, y: 60, width: 260, height: 16),
                    text: 'Description',
                    style: JetTextStyle(weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colQty',
                    bounds: JetRect(x: 270, y: 60, width: 50, height: 16),
                    text: 'Qty',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colUnitPrice',
                    bounds: JetRect(x: 330, y: 60, width: 90, height: 16),
                    text: 'Unit Price',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'colAmount',
                    bounds: JetRect(x: 430, y: 60, width: 110, height: 16),
                    text: 'Amount',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                ],
              ),
              footer: Band(
                id: 'invoiceFooter',
                type: BandType.groupFooter,
                height: 32,
                elements: <ReportElement>[
                  TextElement(
                    id: 'subtotalLabel',
                    bounds: JetRect(x: 330, y: 8, width: 90, height: 18),
                    text: 'Subtotal',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                  ),
                  TextElement(
                    id: 'subtotal',
                    bounds: JetRect(x: 430, y: 8, width: 110, height: 18),
                    text: 'total',
                    style: JetTextStyle(
                        align: JetTextAlign.right, weight: JetFontWeight.bold),
                    expression: r'$F{total}',
                    format: '#,##0.00',
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
/// [invoiceSchema] via `dataSchema:`): the minimal valid tree in the reified
/// band model — one empty `detail` band under the root [DetailScope], no page
/// furniture, no groups, no elements.
///
/// It exists so the playground has a clean canvas for exercising the designer
/// by hand — dropping elements, adding groups/lists, binding fields — starting
/// from nothing rather than from the fully-authored [invoiceSampleDefinition].
/// Because it shares the invoice schema and data source, any field the invoice
/// binds is available to bind here too.
ReportDefinition emptyDesignDefinition() => const ReportDefinition(
      name: 'Empty',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 20)),
          ],
        ),
      ),
    );
