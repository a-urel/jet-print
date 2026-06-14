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
/// output (SC-006). Each record's `total` equals the sum of its line totals.
JetDataSource invoiceDataSource() =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{
        'invoiceNo': 'INV-1042',
        'customerName': 'Acme GmbH',
        // An ISO date string (not DateTime) so the JSON variant can carry the
        // identical value — all three sources then render byte-identically.
        'date': '2026-05-12',
        'total': 32.0,
        'lines': <Map<String, Object?>>[
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
        ],
      },
      <String, Object?>{
        'invoiceNo': 'INV-1043',
        'customerName': 'Globex SARL',
        'date': '2026-05-14',
        'total': 14.5,
        'lines': <Map<String, Object?>>[
          <String, Object?>{
            'description': 'Bolt',
            'qty': 10,
            'unitPrice': 0.75,
            'lineTotal': 7.5
          },
          <String, Object?>{
            'description': 'Nut',
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
        ],
      },
      <String, Object?>{
        'invoiceNo': 'INV-1044',
        'customerName': 'Initech Ltd',
        'date': '2026-05-19',
        'total': 175.0,
        'lines': <Map<String, Object?>>[
          <String, Object?>{
            'description': 'Consulting',
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
        ],
      },
    ]);

/// The same logical invoices as [invoiceDataSource], supplied as a JSON
/// payload — renders byte-identically (SC-006).
JetDataSource invoiceJsonDataSource() => JetJsonDataSource.parse(
      '[{"invoiceNo":"INV-1042","customerName":"Acme GmbH",'
      '"date":"2026-05-12","total":32.0,"lines":['
      '{"description":"Widget","qty":3,"unitPrice":4.5,"lineTotal":13.5},'
      '{"description":"Gadget","qty":1,"unitPrice":12.0,"lineTotal":12.0},'
      '{"description":"Sprocket","qty":2,"unitPrice":3.25,"lineTotal":6.5}]},'
      '{"invoiceNo":"INV-1043","customerName":"Globex SARL",'
      '"date":"2026-05-14","total":14.5,"lines":['
      '{"description":"Bolt","qty":10,"unitPrice":0.75,"lineTotal":7.5},'
      '{"description":"Nut","qty":10,"unitPrice":0.5,"lineTotal":5.0},'
      '{"description":"Washer","qty":20,"unitPrice":0.1,"lineTotal":2.0}]},'
      '{"invoiceNo":"INV-1044","customerName":"Initech Ltd",'
      '"date":"2026-05-19","total":175.0,"lines":['
      '{"description":"Consulting","qty":2,"unitPrice":50.0,"lineTotal":100.0},'
      '{"description":"Onboarding","qty":1,"unitPrice":75.0,"lineTotal":75.0}]}]',
    );

/// The same logical invoices again, supplied as domain objects with a field
/// extractor — renders byte-identically (SC-006).
JetDataSource invoiceObjectDataSource() => JetObjectDataSource<Invoice>(
      <Invoice>[
        Invoice(
            'INV-1042', 'Acme GmbH', '2026-05-12', 32.0, <Map<String, Object?>>[
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
        ]),
        Invoice('INV-1043', 'Globex SARL', '2026-05-14',
            14.5, <Map<String, Object?>>[
          <String, Object?>{
            'description': 'Bolt',
            'qty': 10,
            'unitPrice': 0.75,
            'lineTotal': 7.5
          },
          <String, Object?>{
            'description': 'Nut',
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
        ]),
        Invoice('INV-1044', 'Initech Ltd', '2026-05-19',
            175.0, <Map<String, Object?>>[
          <String, Object?>{
            'description': 'Consulting',
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
