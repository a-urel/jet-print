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

/// A sample invoice layout: one invoice per group, grouped on `invoiceNo`, so
/// each invoice gets its own data-bound header and footer. It exercises the
/// distinction between *page chrome* and *per-record* bands:
///
/// * **page header** ([BandType.pageHeader]) — a static running title. Page
///   chrome: the layouter substitutes it against a page-scoped context with no
///   data row, so it can hold static text and `PAGE_NUMBER`/`PAGE_COUNT` only —
///   **never** `$F{}` fields (the engine would render them blank and raise a
///   diagnostic).
/// * **group header** ([BandType.groupHeader], group `invoice`) — the
///   per-invoice header: the "INVOICE" heading, the invoice number, customer,
///   and date, plus the line-item column labels. Group bands **do** get the
///   current row, so these `$F{}` fields fill — this is the band that does what
///   a "header that shows the customer" needs.
/// * **detail** ([BandType.detail], bound to `lines`) — repeats once per line
///   item.
/// * **group footer** ([BandType.groupFooter], group `invoice`) — the
///   per-invoice footer with the subtotal (`$F{total}`); also data-bound.
/// * **page footer** ([BandType.pageFooter]) — page chrome again: a
///   `Page N of M` line built from the page-scoped `PAGE_NUMBER`/`PAGE_COUNT`.
///
/// The `invoice` group sets `startNewPage` so each invoice begins on its own
/// page (and `keepTogether` so a single invoice never splits across a page
/// boundary).
///
/// All bindings show as design-time tokens; rendered through `JetReportEngine`
/// they fill with real values.
ReportTemplate invoiceSampleTemplate() => const ReportTemplate(
      name: 'Invoice',
      page: PageFormat.a4Portrait,
      // One group per invoice: the key changes on every master row, so the
      // group header/footer bracket each invoice's lines.
      groups: <ReportGroup>[
        ReportGroup(
          name: 'invoice',
          expression: r'$F{invoiceNo}',
          keepTogether: true,
          // Each invoice starts on its own page (the first does not force a
          // leading blank page).
          startNewPage: true,
        ),
      ],
      bands: <ReportBand>[
        // Page header — page chrome (static only; no row context). A running
        // title repeated at the top of every page.
        ReportBand(
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
        // Group header — the per-invoice header. Group bands carry the current
        // row, so the invoice number, customer, and date all fill.
        ReportBand(
          type: BandType.groupHeader,
          group: 'invoice',
          height: 80,
          elements: <ReportElement>[
            TextElement(
              id: 'heading',
              bounds: JetRect(x: 0, y: 0, width: 200, height: 28),
              text: 'INVOICE',
              style: JetTextStyle(fontSize: 22, weight: JetFontWeight.bold),
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
            // Column labels, aligned to the `lines` detail band below.
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
        // Detail — repeats per invoice line (the `lines` collection).
        ReportBand(
          type: BandType.detail,
          height: 22,
          collectionField: 'lines',
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
        ),
        // Group footer — the per-invoice subtotal (data-bound, like the header).
        ReportBand(
          type: BandType.groupFooter,
          group: 'invoice',
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
        // Page footer — page chrome: a `Page N of M` line from the page-scoped
        // PAGE_NUMBER/PAGE_COUNT variables (no data row needed).
        ReportBand(
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
      ],
    );
