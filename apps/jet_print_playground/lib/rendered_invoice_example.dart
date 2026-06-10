/// The playground's rendered-invoice example (011 — FR-019 / SC-008): supply
/// real data for the bound invoice template, render it through the public
/// engine, and show the paginated preview. The whole integration — data
/// source + render + preview — is the < 30 lines inside [invoiceDataSource],
/// [renderInvoice], and [RenderedInvoiceExample.build], all through
/// `package:jet_print/jet_print.dart` only.
library;

import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';

import 'invoice_sample.dart';

/// One invoice record with a nested `lines` collection (master/detail),
/// matching [invoiceSchema]. Use `JetJsonDataSource` for a JSON payload or
/// `JetObjectDataSource<T>` for domain objects — identical output (SC-006).
JetDataSource invoiceDataSource() => JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{
        'invoiceNo': 'INV-1042',
        'customerName': 'Acme GmbH',
        // An ISO date string (not DateTime) so the JSON variant can carry the
        // identical value — all three sources then render byte-identically.
        'date': '2026-05-12',
        'total': 32.0,
        'lines': <Map<String, Object?>>[
          <String, Object?>{'description': 'Widget', 'qty': 3, 'unitPrice': 4.5, 'lineTotal': 13.5},
          <String, Object?>{'description': 'Gadget', 'qty': 1, 'unitPrice': 12.0, 'lineTotal': 12.0},
          <String, Object?>{'description': 'Sprocket', 'qty': 2, 'unitPrice': 3.25, 'lineTotal': 6.5},
        ],
      },
    ]);

/// The same logical invoice as [invoiceDataSource], supplied as a JSON
/// payload — renders byte-identically (SC-006).
JetDataSource invoiceJsonDataSource() => JetJsonDataSource.parse(
      '[{"invoiceNo":"INV-1042","customerName":"Acme GmbH",'
      '"date":"2026-05-12","total":32.0,"lines":['
      '{"description":"Widget","qty":3,"unitPrice":4.5,"lineTotal":13.5},'
      '{"description":"Gadget","qty":1,"unitPrice":12.0,"lineTotal":12.0},'
      '{"description":"Sprocket","qty":2,"unitPrice":3.25,"lineTotal":6.5}]}]',
    );

/// The same logical invoice again, supplied as domain objects with a field
/// extractor — renders byte-identically (SC-006).
JetDataSource invoiceObjectDataSource() => JetObjectDataSource<Invoice>(
      <Invoice>[
        Invoice('INV-1042', 'Acme GmbH', '2026-05-12', 32.0,
            <Map<String, Object?>>[
          <String, Object?>{'description': 'Widget', 'qty': 3, 'unitPrice': 4.5, 'lineTotal': 13.5},
          <String, Object?>{'description': 'Gadget', 'qty': 1, 'unitPrice': 12.0, 'lineTotal': 12.0},
          <String, Object?>{'description': 'Sprocket', 'qty': 2, 'unitPrice': 3.25, 'lineTotal': 6.5},
        ]),
      ],
      fields: invoiceSchema.fields,
      row: (Invoice i) => <String, Object?>{
        'invoiceNo': i.invoiceNo,
        'customerName': i.customerName,
        'date': i.date,
        'total': i.total,
        'lines': i.lines,
      },
    );

/// A host domain object for the object-backed variant.
class Invoice {
  /// Creates an invoice record.
  const Invoice(
      this.invoiceNo, this.customerName, this.date, this.total, this.lines);

  /// The invoice number.
  final String invoiceNo;

  /// The customer display name.
  final String customerName;

  /// The invoice date (ISO string, matching the other variants).
  final String date;

  /// The invoice total (sum of line totals).
  final double total;

  /// The nested line-item collection.
  final List<Map<String, Object?>> lines;
}

/// Renders the bound invoice template with [source] (defaults to the
/// in-memory sample): line items iterate, master fields fill, and the first
/// page is viewable without materializing the rest (FR-021).
RenderedReport renderInvoice({JetDataSource? source}) =>
    const JetReportEngine().render(
      invoiceSampleTemplate(),
      source ?? invoiceDataSource(),
      options: const RenderOptions(locale: Locale('en')),
    );

/// The on-screen preview of the rendered invoice — prev/next navigation,
/// "page X of N", fit-to-width.
class RenderedInvoiceExample extends StatelessWidget {
  /// Creates the rendered-invoice preview example.
  const RenderedInvoiceExample({super.key});

  @override
  Widget build(BuildContext context) => JetReportPreview(report: renderInvoice());
}
