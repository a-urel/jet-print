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

/// A sample invoice layout: a title band with master header fields, a
/// `lines`-bound **detail** band whose elements bind to the line fields, and a
/// summary band with the master total. All bindings show as design-time tokens.
ReportTemplate invoiceSampleTemplate() => const ReportTemplate(
      name: 'Invoice',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        // Master header — invoice-level fields (master scope).
        ReportBand(
          type: BandType.title,
          height: 96,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
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
              bounds: JetRect(x: 0, y: 44, width: 280, height: 18),
              text: 'customerName',
              expression: r'$F{customerName}',
            ),
            TextElement(
              id: 'date',
              bounds: JetRect(x: 360, y: 44, width: 180, height: 18),
              text: 'date',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'$F{date}',
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
            ),
            TextElement(
              id: 'lineTotal',
              bounds: JetRect(x: 430, y: 2, width: 110, height: 16),
              text: 'lineTotal',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'$F{lineTotal}',
            ),
          ],
        ),
        // Master summary — the invoice total.
        ReportBand(
          type: BandType.summary,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 'totalLabel',
              bounds: JetRect(x: 330, y: 10, width: 90, height: 18),
              text: 'Total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'total',
              bounds: JetRect(x: 430, y: 10, width: 110, height: 18),
              text: 'total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'$F{total}',
            ),
          ],
        ),
      ],
    );
