// The smallest useful jet_print consumer: one screen that builds a report
// definition in code, renders it over a handful of literal rows, previews it,
// and exports the same rendered report as a PDF.
//
// Everything here comes from the package's single public entry point,
// `package:jet_print/jet_print.dart`. Nothing reaches into
// `package:jet_print/src/...`, because a consumer cannot.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';
import 'package:printing/printing.dart' show Printing;
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  // The render path never validates: a definition built in code is checked by
  // nothing unless the host checks it. In a release build this is compiled
  // out, so it costs the shipped app nothing.
  assert(
    !validate(_salesSummary).any(_isError),
    'the example report definition has validation errors',
  );
  runApp(const JetPrintExampleApp());
}

/// Whether [d] is an error, as opposed to a warning or an informational note
/// (which a perfectly valid definition may still carry).
bool _isError(Diagnostic d) => d.severity == DiagnosticSeverity.error;

/// The example app: a [ShadApp] shell around one [JetReportPreview].
///
/// jet_print's widgets are themed with `shadcn_ui`, so the host supplies a
/// [ShadApp] (or a [ShadTheme]) above them, and wires
/// [JetPrintLocalizations.delegate] so the preview's chrome localizes.
class JetPrintExampleApp extends StatelessWidget {
  /// Creates the example app.
  const JetPrintExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'jet_print example',
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: JetReportPreview(report: _report, onExportPdf: _exportPdf),
    );
  }
}

/// The rendered report, built once on first use.
///
/// Rendering is synchronous and deterministic — the same definition, rows and
/// options always produce the same pages — so there is nothing to await and no
/// reason to redo it when the widget tree rebuilds.
final RenderedReport _report = const JetReportEngine().renderDefinition(
  _salesSummary,
  JetInMemoryDataSource(_rows),
);

/// Exports [_report] as a PDF and hands the bytes to the platform.
///
/// Export is headless: [JetReportExporter.toPdf] returns bytes and the host
/// decides what becomes of them. This example offers them to the platform's
/// share/save sheet; a desktop host would more likely write them to a file the
/// user picked.
Future<void> _exportPdf() async {
  final Uint8List pdf = await const JetReportExporter().toPdf(_report);
  await Printing.sharePdf(bytes: pdf, filename: 'sales-summary.pdf');
}

/// The report's data: a handful of literal rows. A real host hands the engine
/// a [JetJsonDataSource] or a [JetObjectDataSource] over its own records
/// instead; the shape the report sees is the same.
const List<Map<String, Object?>> _rows = <Map<String, Object?>>[
  <String, Object?>{'product': 'Widget', 'region': 'North', 'amount': 1240.5},
  <String, Object?>{'product': 'Widget', 'region': 'South', 'amount': 880.0},
  <String, Object?>{'product': 'Gadget', 'region': 'North', 'amount': 2310.75},
  <String, Object?>{'product': 'Gadget', 'region': 'East', 'amount': 145.25},
  <String, Object?>{'product': 'Sprocket', 'region': 'West', 'amount': 67.4},
];

/// The content width of an A4 portrait page under the format's own 28.35pt
/// margins: 595.28 - 2 x 28.35 = 538.58, rounded down to a whole point.
const double _contentWidth = 538;

/// The report: a heading and column captions printed once, one band per row, a
/// grand total at the end, and a page-number footer on every page.
///
/// Every role here is structural rather than inferred. The footer is a page
/// footer because it sits in [PageFurniture.pageFooter]; the detail band
/// repeats because it is a [BandNode] inside the master [DetailScope]; the
/// total prints once because it sits in [ReportBody.summary]. Every
/// measurement is in points, which is the model's only unit.
const ReportDefinition _salesSummary = ReportDefinition(
  name: 'Sales summary',
  page: PageFormat.a4Portrait,
  // A report-scoped sum over every row, read back below as `$V{grandTotal}`.
  variables: <ReportVariable>[
    ReportVariable(
      name: 'grandTotal',
      expression: r'$F{amount}',
      calculation: JetCalculation.sum,
    ),
  ],
  furniture: PageFurniture(
    pageFooter: Band(
      id: 'pageFooter',
      type: BandType.pageFooter,
      height: 20,
      elements: <ReportElement>[
        TextElement(
          id: 'pageFooter/number',
          bounds: JetRect(x: 0, y: 4, width: _contentWidth, height: 12),
          text: 'Page',
          style: JetTextStyle(fontSize: 9, align: JetTextAlign.right),
          expression: r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
        ),
      ],
    ),
  ),
  body: ReportBody(
    title: Band(
      id: 'title',
      type: BandType.title,
      height: 48,
      elements: <ReportElement>[
        TextElement(
          id: 'title/heading',
          bounds: JetRect(x: 0, y: 0, width: 300, height: 26),
          text: 'Sales summary',
          style: JetTextStyle(fontSize: 20, weight: JetFontWeight.bold),
        ),
        TextElement(
          id: 'title/product',
          bounds: JetRect(x: 0, y: 32, width: 230, height: 14),
          text: 'Product',
          style: JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
        ),
        TextElement(
          id: 'title/region',
          bounds: JetRect(x: 240, y: 32, width: 120, height: 14),
          text: 'Region',
          style: JetTextStyle(fontSize: 9, weight: JetFontWeight.bold),
        ),
        TextElement(
          id: 'title/amount',
          bounds: JetRect(x: 370, y: 32, width: 168, height: 14),
          text: 'Amount',
          style: JetTextStyle(
            fontSize: 9,
            weight: JetFontWeight.bold,
            align: JetTextAlign.right,
          ),
        ),
      ],
    ),
    summary: Band(
      id: 'summary',
      type: BandType.summary,
      height: 30,
      elements: <ReportElement>[
        TextElement(
          id: 'summary/label',
          bounds: JetRect(x: 240, y: 8, width: 120, height: 14),
          text: 'Total',
          style: JetTextStyle(
            weight: JetFontWeight.bold,
            align: JetTextAlign.right,
          ),
        ),
        TextElement(
          id: 'summary/total',
          bounds: JetRect(x: 370, y: 8, width: 168, height: 14),
          text: 'grandTotal',
          style: JetTextStyle(
            weight: JetFontWeight.bold,
            align: JetTextAlign.right,
          ),
          expression: r'$V{grandTotal}',
          format: '#,##0.00',
        ),
      ],
    ),
    root: DetailScope(
      id: 'root',
      children: <ScopeNode>[
        BandNode(Band(
          id: 'detail',
          type: BandType.detail,
          height: 18,
          elements: <ReportElement>[
            TextElement(
              id: 'detail/product',
              bounds: JetRect(x: 0, y: 2, width: 230, height: 14),
              text: 'product',
              expression: r'$F{product}',
            ),
            TextElement(
              id: 'detail/region',
              bounds: JetRect(x: 240, y: 2, width: 120, height: 14),
              text: 'region',
              expression: r'$F{region}',
            ),
            TextElement(
              id: 'detail/amount',
              bounds: JetRect(x: 370, y: 2, width: 168, height: 14),
              text: 'amount',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'$F{amount}',
              format: '#,##0.00',
            ),
          ],
        )),
      ],
    ),
  ),
);
