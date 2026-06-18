/// The playground's rendered-invoice example (011 — FR-019 / SC-008): supply
/// real data for the bound invoice template, render it through the public
/// engine, and show the paginated preview. The whole integration — data
/// source + render + preview — is the < 30 lines inside [invoiceDataSource],
/// [renderInvoice], and [RenderedInvoiceExample], all through
/// `package:jet_print/jet_print.dart` only.
///
/// 012 adds export and print: the report renders ONCE and that single
/// `RenderedReport` feeds the preview, the PDF bytes (saved via
/// `file_selector` — host-owned I/O), and the system print dialog (SC-001:
/// under 10 integration lines beyond the 011 example).
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';

import 'invoice_sample.dart';

/// Three invoice records, each with a nested `lines` collection
/// (master/detail), matching [invoiceSchema]. Use `JetJsonDataSource` for a
/// JSON payload or `JetObjectDataSource<T>` for domain objects — identical
/// output (SC-006).
///
/// Monetary invariants every record honors (the example's tests pin them):
/// `total` (the subtotal) equals the sum of its line totals, and
/// `grandTotal == total + tax + shipping + discount` (with `discount` stored
/// negative). All amounts are chosen as "dyadic" values (multiples of 0.25/0.5)
/// so those sums are exact in IEEE-754 and the three sources render
/// byte-identically.
JetDataSource invoiceDataSource() =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{
        'invoiceNo': 'INV-1042',
        'customerName': 'Acme GmbH',
        'billingAddress': 'Industriestraße 12\n80331 München\nGermany',
        // An ISO date string (not DateTime) so the JSON variant can carry the
        // identical value — all three sources then render byte-identically.
        'date': '2026-05-12',
        'total': 200.0,
        'discountLabel': 'Discount 10%',
        'discount': -20.0,
        'taxLabel': 'VAT 19%',
        'tax': 38.0,
        'shipping': 12.5,
        'grandTotal': 230.5,
        'paymentTerms': 'Net 30 — due 2026-06-11',
        'shippingMethod': 'DHL Express, 2-3 business days',
        'notes': 'Thank you for your business! Please quote the invoice '
            'number with your payment.',
        'invoiceDescription': 'Manufacturing components and on-site assembly '
            'for the Q2 production-line upgrade. All parts inspected and '
            'certified to DIN EN ISO 9001.',
        'lines': _lines1042,
      },
      <String, Object?>{
        'invoiceNo': 'INV-1043',
        'customerName': 'Globex SARL',
        'billingAddress': '14 Rue de l’Industrie\n69002 Lyon\nFrance',
        'date': '2026-05-14',
        'total': 150.0,
        'discountLabel': 'Discount 5%',
        'discount': -7.5,
        'taxLabel': 'TVA 20%',
        'tax': 30.0,
        'shipping': 9.5,
        'grandTotal': 182.0,
        'paymentTerms': 'Net 14 — due 2026-05-28',
        'shippingMethod': 'DPD Standard, 3-5 business days',
        'notes': 'Goods remain our property until paid in full.',
        'invoiceDescription': 'Replacement hardware and cabling for the Lyon '
            'conveyor maintenance contract (ref. GLX-2026-114).',
        'lines': _lines1043,
      },
      <String, Object?>{
        'invoiceNo': 'INV-1044',
        'customerName': 'Initech Ltd',
        'billingAddress':
            'Initech House, 5 Tech Park\nLondon EC1A 1BB\nUnited Kingdom',
        'date': '2026-05-19',
        'total': 500.0,
        'discountLabel': 'Discount 8%',
        'discount': -40.0,
        'taxLabel': 'VAT 20%',
        'tax': 100.0,
        'shipping': 0.0,
        'grandTotal': 560.0,
        'paymentTerms': 'Due on receipt',
        'shippingMethod': 'Digital delivery - no shipment',
        'notes': 'Reverse charge may apply. Questions? billing@example.com',
        'invoiceDescription': 'Professional services: discovery, custom '
            'integration build-out, and team enablement for the '
            'reporting-platform rollout.',
        'lines': _lines1044,
      },
    ]);

/// The same logical invoices as [invoiceDataSource], supplied as a JSON
/// payload — renders byte-identically (SC-006). The `\\n` sequences are
/// JSON-escaped newlines (one Dart backslash-n reaches the parser as a literal
/// newline inside the multi-line billing addresses).
JetDataSource invoiceJsonDataSource() => JetJsonDataSource.parse(
      '[{"invoiceNo":"INV-1042","customerName":"Acme GmbH",'
      '"billingAddress":"Industriestraße 12\\n80331 München\\nGermany",'
      '"date":"2026-05-12","total":200.0,'
      '"discountLabel":"Discount 10%","discount":-20.0,'
      '"taxLabel":"VAT 19%","tax":38.0,'
      '"shipping":12.5,"grandTotal":230.5,'
      '"paymentTerms":"Net 30 — due 2026-06-11",'
      '"shippingMethod":"DHL Express, 2-3 business days",'
      '"notes":"Thank you for your business! Please quote the invoice number with your payment.",'
      '"invoiceDescription":"Manufacturing components and on-site assembly for the Q2 production-line upgrade. All parts inspected and certified to DIN EN ISO 9001.",'
      '"lines":['
      '{"description":"Widget","qty":3,"unitPrice":4.5,"lineTotal":13.5},'
      '{"description":"Gadget","qty":1,"unitPrice":12.0,"lineTotal":12.0},'
      '{"description":"Sprocket","qty":2,"unitPrice":3.25,"lineTotal":6.5},'
      '{"description":"Flange bracket","qty":4,"unitPrice":8.0,"lineTotal":32.0},'
      '{"description":"Mounting plate","qty":2,"unitPrice":18.0,"lineTotal":36.0},'
      '{"description":"Hex bolt set (50 pc)","qty":5,"unitPrice":6.0,"lineTotal":30.0},'
      '{"description":"Assembly service","qty":1,"unitPrice":70.0,"lineTotal":70.0}]},'
      '{"invoiceNo":"INV-1043","customerName":"Globex SARL",'
      '"billingAddress":"14 Rue de l’Industrie\\n69002 Lyon\\nFrance",'
      '"date":"2026-05-14","total":150.0,'
      '"discountLabel":"Discount 5%","discount":-7.5,'
      '"taxLabel":"TVA 20%","tax":30.0,'
      '"shipping":9.5,"grandTotal":182.0,'
      '"paymentTerms":"Net 14 — due 2026-05-28",'
      '"shippingMethod":"DPD Standard, 3-5 business days",'
      '"notes":"Goods remain our property until paid in full.",'
      '"invoiceDescription":"Replacement hardware and cabling for the Lyon conveyor maintenance contract (ref. GLX-2026-114).",'
      '"lines":['
      '{"description":"Bolt M6","qty":10,"unitPrice":0.75,"lineTotal":7.5},'
      '{"description":"Nut M6","qty":10,"unitPrice":0.5,"lineTotal":5.0},'
      '{"description":"Washer","qty":20,"unitPrice":0.1,"lineTotal":2.0},'
      '{"description":"Steel cable (m)","qty":25,"unitPrice":1.4,"lineTotal":35.0},'
      '{"description":"Cable clamp","qty":16,"unitPrice":1.5,"lineTotal":24.0},'
      '{"description":"Tension spring","qty":8,"unitPrice":4.5,"lineTotal":36.0},'
      '{"description":"Pulley wheel","qty":5,"unitPrice":8.1,"lineTotal":40.5}]},'
      '{"invoiceNo":"INV-1044","customerName":"Initech Ltd",'
      '"billingAddress":"Initech House, 5 Tech Park\\nLondon EC1A 1BB\\nUnited Kingdom",'
      '"date":"2026-05-19","total":500.0,'
      '"discountLabel":"Discount 8%","discount":-40.0,'
      '"taxLabel":"VAT 20%","tax":100.0,'
      '"shipping":0.0,"grandTotal":560.0,'
      '"paymentTerms":"Due on receipt",'
      '"shippingMethod":"Digital delivery - no shipment",'
      '"notes":"Reverse charge may apply. Questions? billing@example.com",'
      '"invoiceDescription":"Professional services: discovery, custom integration build-out, and team enablement for the reporting-platform rollout.",'
      '"lines":['
      '{"description":"Consulting (day)","qty":2,"unitPrice":50.0,"lineTotal":100.0},'
      '{"description":"Onboarding","qty":1,"unitPrice":75.0,"lineTotal":75.0},'
      '{"description":"Custom integration","qty":5,"unitPrice":40.0,"lineTotal":200.0},'
      '{"description":"Training workshop","qty":1,"unitPrice":80.0,"lineTotal":80.0},'
      '{"description":"Priority support (mo)","qty":1,"unitPrice":45.0,"lineTotal":45.0}]}]',
    );

/// The same logical invoices again, supplied as domain objects with a field
/// extractor — renders byte-identically (SC-006). The line-item lists are
/// shared with [invoiceDataSource] via top-level constants so the two variants
/// can never drift.
JetDataSource invoiceObjectDataSource() => JetObjectDataSource<Invoice>(
      const <Invoice>[
        Invoice(
          invoiceNo: 'INV-1042',
          customerName: 'Acme GmbH',
          billingAddress: 'Industriestraße 12\n80331 München\nGermany',
          date: '2026-05-12',
          total: 200.0,
          discountLabel: 'Discount 10%',
          discount: -20.0,
          taxLabel: 'VAT 19%',
          tax: 38.0,
          shipping: 12.5,
          grandTotal: 230.5,
          paymentTerms: 'Net 30 — due 2026-06-11',
          shippingMethod: 'DHL Express, 2-3 business days',
          notes: 'Thank you for your business! Please quote the invoice '
              'number with your payment.',
          invoiceDescription: 'Manufacturing components and on-site assembly '
              'for the Q2 production-line upgrade. All parts inspected and '
              'certified to DIN EN ISO 9001.',
          lines: _lines1042,
        ),
        Invoice(
          invoiceNo: 'INV-1043',
          customerName: 'Globex SARL',
          billingAddress: '14 Rue de l’Industrie\n69002 Lyon\nFrance',
          date: '2026-05-14',
          total: 150.0,
          discountLabel: 'Discount 5%',
          discount: -7.5,
          taxLabel: 'TVA 20%',
          tax: 30.0,
          shipping: 9.5,
          grandTotal: 182.0,
          paymentTerms: 'Net 14 — due 2026-05-28',
          shippingMethod: 'DPD Standard, 3-5 business days',
          notes: 'Goods remain our property until paid in full.',
          invoiceDescription: 'Replacement hardware and cabling for the Lyon '
              'conveyor maintenance contract (ref. GLX-2026-114).',
          lines: _lines1043,
        ),
        Invoice(
          invoiceNo: 'INV-1044',
          customerName: 'Initech Ltd',
          billingAddress:
              'Initech House, 5 Tech Park\nLondon EC1A 1BB\nUnited Kingdom',
          date: '2026-05-19',
          total: 500.0,
          discountLabel: 'Discount 8%',
          discount: -40.0,
          taxLabel: 'VAT 20%',
          tax: 100.0,
          shipping: 0.0,
          grandTotal: 560.0,
          paymentTerms: 'Due on receipt',
          shippingMethod: 'Digital delivery - no shipment',
          notes: 'Reverse charge may apply. Questions? billing@example.com',
          invoiceDescription: 'Professional services: discovery, custom '
              'integration build-out, and team enablement for the '
              'reporting-platform rollout.',
          lines: _lines1044,
        ),
      ],
      fields: invoiceSchema.fields,
      row: (Invoice i) => <String, Object?>{
        'invoiceNo': i.invoiceNo,
        'customerName': i.customerName,
        'billingAddress': i.billingAddress,
        'date': i.date,
        'total': i.total,
        'discountLabel': i.discountLabel,
        'discount': i.discount,
        'taxLabel': i.taxLabel,
        'tax': i.tax,
        'shipping': i.shipping,
        'grandTotal': i.grandTotal,
        'paymentTerms': i.paymentTerms,
        'shippingMethod': i.shippingMethod,
        'notes': i.notes,
        'invoiceDescription': i.invoiceDescription,
        'lines': i.lines,
      },
    );

const List<Map<String, Object?>> _lines1042 = <Map<String, Object?>>[
  <String, Object?>{
    'description': 'Widget',
    'qty': 3,
    'unitPrice': 4.5,
    'lineTotal': 13.5
  },
  <String, Object?>{
    'description': 'Gadget',
    'qty': 1,
    'unitPrice': 12.0,
    'lineTotal': 12.0
  },
  <String, Object?>{
    'description': 'Sprocket',
    'qty': 2,
    'unitPrice': 3.25,
    'lineTotal': 6.5
  },
  <String, Object?>{
    'description': 'Flange bracket',
    'qty': 4,
    'unitPrice': 8.0,
    'lineTotal': 32.0
  },
  <String, Object?>{
    'description': 'Mounting plate',
    'qty': 2,
    'unitPrice': 18.0,
    'lineTotal': 36.0
  },
  <String, Object?>{
    'description': 'Hex bolt set (50 pc)',
    'qty': 5,
    'unitPrice': 6.0,
    'lineTotal': 30.0
  },
  <String, Object?>{
    'description': 'Assembly service',
    'qty': 1,
    'unitPrice': 70.0,
    'lineTotal': 70.0
  },
];

const List<Map<String, Object?>> _lines1043 = <Map<String, Object?>>[
  <String, Object?>{
    'description': 'Bolt M6',
    'qty': 10,
    'unitPrice': 0.75,
    'lineTotal': 7.5
  },
  <String, Object?>{
    'description': 'Nut M6',
    'qty': 10,
    'unitPrice': 0.5,
    'lineTotal': 5.0
  },
  <String, Object?>{
    'description': 'Washer',
    'qty': 20,
    'unitPrice': 0.1,
    'lineTotal': 2.0
  },
  <String, Object?>{
    'description': 'Steel cable (m)',
    'qty': 25,
    'unitPrice': 1.4,
    'lineTotal': 35.0
  },
  <String, Object?>{
    'description': 'Cable clamp',
    'qty': 16,
    'unitPrice': 1.5,
    'lineTotal': 24.0
  },
  <String, Object?>{
    'description': 'Tension spring',
    'qty': 8,
    'unitPrice': 4.5,
    'lineTotal': 36.0
  },
  <String, Object?>{
    'description': 'Pulley wheel',
    'qty': 5,
    'unitPrice': 8.1,
    'lineTotal': 40.5
  },
];

const List<Map<String, Object?>> _lines1044 = <Map<String, Object?>>[
  <String, Object?>{
    'description': 'Consulting (day)',
    'qty': 2,
    'unitPrice': 50.0,
    'lineTotal': 100.0
  },
  <String, Object?>{
    'description': 'Onboarding',
    'qty': 1,
    'unitPrice': 75.0,
    'lineTotal': 75.0
  },
  <String, Object?>{
    'description': 'Custom integration',
    'qty': 5,
    'unitPrice': 40.0,
    'lineTotal': 200.0
  },
  <String, Object?>{
    'description': 'Training workshop',
    'qty': 1,
    'unitPrice': 80.0,
    'lineTotal': 80.0
  },
  <String, Object?>{
    'description': 'Priority support (mo)',
    'qty': 1,
    'unitPrice': 45.0,
    'lineTotal': 45.0
  },
];

/// A host domain object for the object-backed variant — the full invoice
/// header plus its nested line items.
class Invoice {
  /// Creates an invoice record.
  const Invoice({
    required this.invoiceNo,
    required this.customerName,
    required this.billingAddress,
    required this.date,
    required this.total,
    required this.discountLabel,
    required this.discount,
    required this.taxLabel,
    required this.tax,
    required this.shipping,
    required this.grandTotal,
    required this.paymentTerms,
    required this.shippingMethod,
    required this.notes,
    required this.invoiceDescription,
    required this.lines,
  });

  /// The invoice number.
  final String invoiceNo;

  /// The customer display name.
  final String customerName;

  /// The customer's multi-line billing address.
  final String billingAddress;

  /// The invoice date (ISO string, matching the other variants).
  final String date;

  /// The subtotal — the sum of the line totals.
  final double total;

  /// The human-readable discount caption (e.g. `Discount 10%`).
  final String discountLabel;

  /// The discount, stored **negative** so it reads as a deduction and keeps
  /// [grandTotal] a plain sum.
  final double discount;

  /// The human-readable tax-rate caption (e.g. `VAT 19%`).
  final String taxLabel;

  /// The tax amount added on top of [total].
  final double tax;

  /// The shipping charge added on top of [total].
  final double shipping;

  /// The amount actually due: [total] + [tax] + [shipping] + [discount]
  /// (with [discount] negative).
  final double grandTotal;

  /// The payment terms line (e.g. `Net 30 — due 2026-06-11`).
  final String paymentTerms;

  /// The shipping-method line.
  final String shippingMethod;

  /// The free-text footer note.
  final String notes;

  /// The free-text invoice summary shown below the totals.
  final String invoiceDescription;

  /// The nested line-item collection.
  final List<Map<String, Object?>> lines;
}

/// Renders the invoice **authored in the reified band model** ([invoiceSampleDefinition])
/// through the native [JetReportEngine.renderDefinition] path (spec 024). This
/// is the end-to-end confirmation of the new architecture: a hand-built
/// `ReportDefinition` (page furniture + a master `DetailScope` with a
/// first-class `GroupLevel` and a nested `lines` scope) renders the same
/// one-invoice-per-page output as the flat-template path ([renderInvoice]).
RenderedReport renderInvoiceDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? invoiceSampleDefinition(),
      source ?? invoiceDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(invoiceSchema.fields),
        fonts: fonts,
      ),
    );

/// The flat set of every field name the schema declares, top-level and nested
/// (so collection-scoped bindings like `$F{lineTotal}` are recognized too).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };

/// The on-screen preview of the rendered invoice — prev/next navigation,
/// "page X of N", zoom, a back button (when [onBack] is given), and the 012
/// export/print toolbar actions wired to the SAME single render.
class RenderedInvoiceExample extends StatefulWidget {
  /// Creates the rendered-invoice preview example; [onBack] backs the
  /// preview toolbar's back button. Pass the designer's LIVE [template] so
  /// design edits show up in the preview; null falls back to the bundled
  /// invoice sample.
  const RenderedInvoiceExample({
    super.key,
    this.onBack,
    this.definition,
    this.onRename,
  });

  /// Invoked by the preview's back button (e.g. to return to the designer).
  final VoidCallback? onBack;

  /// The design to render against the sample invoice data (null = the
  /// bundled sample design).
  final ReportDefinition? definition;

  /// Invoked when the report is renamed from the preview toolbar (017); the
  /// host routes it to the same `controller.rename` the designer uses.
  final ValueChanged<String>? onRename;

  @override
  State<RenderedInvoiceExample> createState() => _RenderedInvoiceExampleState();
}

class _RenderedInvoiceExampleState extends State<RenderedInvoiceExample> {
  /// Rendered ONCE: this single report feeds the preview, the PDF export,
  /// and the print job (FR-001) — no re-render per artifact.
  late final RenderedReport _report =
      renderInvoiceDefinition(definition: widget.definition);

  /// Export = save the in-memory PDF bytes wherever the user picks
  /// (host-owned I/O; the library stays headless).
  Future<void> _savePdf() async {
    final Uint8List pdf = await const JetReportExporter().toPdf(_report);
    final FileSaveLocation? location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PDF document', extensions: <String>['pdf']),
      ],
      suggestedName: 'invoice.pdf',
    );
    if (location == null) return; // user cancelled
    await XFile.fromData(pdf, mimeType: 'application/pdf')
        .saveTo(location.path);
  }

  @override
  Widget build(BuildContext context) => JetReportPreview(
        report: _report,
        onBack: widget.onBack,
        onExportPdf: _savePdf,
        onPrint: () => const JetReportPrinter().printReport(_report),
        onRename: widget.onRename,
      );
}
