// The pilot's app shell: one screen showing the rendered mizan, with a PDF
// export action.
//
// Everything here comes from the package's single public entry point,
// `package:jet_print/jet_print.dart`. Nothing reaches into
// `package:jet_print/src/...`, because an outside consumer cannot, and the
// point of this pilot is to find out what that costs.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jet_print/jet_print.dart';
import 'package:printing/printing.dart' show Printing;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'ledger_data.dart';
import 'trial_balance_report.dart';

void main() {
  // The render path never calls validate(). A definition built in code is
  // checked by nothing unless the host checks it, so the pilot checks it here.
  // The predicate is hand-rolled: validate() returns a bare List<Diagnostic>
  // with no severity filter, while the render side's ReportDiagnostics does
  // carry a hasErrors getter — the same question, answered by the library on
  // one type and by the host on the other.
  //
  // This assert passes but is not clean: validate() also reports two warnings
  // against the summary band, for the aggregate operands of the "Fark" cell.
  // See `trial_balance_report.dart`.
  assert(
    !validate(trialBalanceDefinition(), schema: trialBalanceSchema)
        .any(_isError),
    'the mizan definition has validation errors',
  );
  // Touching the report here also forces the render before the first frame, so
  // a data problem surfaces at startup rather than on first paint.
  assert(
    !_report.diagnostics.hasErrors,
    'rendering the mizan produced error diagnostics',
  );
  runApp(const LedgerPilotApp());
}

/// Whether [d] is an error, as opposed to a warning or an informational note
/// that a perfectly valid definition may still carry.
bool _isError(Diagnostic d) => d.severity == DiagnosticSeverity.error;

/// The pilot app: a [ShadApp] shell around one [JetReportPreview].
///
/// The shell is not a design choice. [JetReportPreview] calls
/// `ShadTheme.of(context)`, so a host that wraps it in a `MaterialApp` fails at
/// runtime with no compile error and no dartdoc warning. Showing a preview
/// therefore costs the host a direct dependency on a pre-1.0 third-party UI
/// package.
class LedgerPilotApp extends StatelessWidget {
  /// Creates the pilot app.
  const LedgerPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'Mizan',
      // The report is Turkish, so the preview's own chrome is too. The library
      // ships en/de/tr; the Global* delegates cover everything else the shell
      // asks for under a non-English locale.
      locale: const Locale('tr'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      // onExportPdf is a VoidCallback; _exportPdf returns a Future. Dart lets
      // the assignment through because void is a top type, so the host has no
      // way to show progress and an export failure lands as an unhandled async
      // error rather than anywhere this widget can see it. Left as it is: a
      // workaround here would hide the cost the pilot exists to measure.
      home: JetReportPreview(report: _report, onExportPdf: _exportPdf),
    );
  }
}

/// The rendered mizan, built once on first use.
///
/// Rendering is synchronous and deterministic — the same definition, rows and
/// options always produce the same pages — so there is nothing to await and no
/// reason to redo it when the widget tree rebuilds.
///
/// Three inputs describe the same schema, in three shapes, none of which the
/// library derives from another: `fields:` on the source, `schema:` on
/// `validate`, and `knownFields` here. Supplying `knownFields` is what turns a
/// mistyped binding from a silently empty cell into a visible `#ERROR`; the
/// silent behaviour is the default.
final RenderedReport _report = const JetReportEngine().renderDefinition(
  trialBalanceDefinition(),
  JetInMemoryDataSource(buildLedgerRows(), fields: ledgerFields),
  options: RenderOptions(
    // Turkish number formatting: `#,##0.00` groups with `.` and separates the
    // decimal with `,`. The pattern on each element does not say that — the
    // locale here does, and the two are written in different files.
    locale: const Locale('tr'),
    knownFields: knownLedgerFields,
    parameters: const <String, Object?>{
      'firmaAdi': 'Anadolu Ticaret A.Ş.',
      'donem': '01.01.2026 - 31.12.2026',
    },
  ),
);

/// Exports [_report] as a PDF and hands the bytes to the platform.
///
/// Export is headless: [JetReportExporter.toPdf] returns bytes and the host
/// decides what becomes of them. This pilot offers them to the platform's
/// share/save sheet, which is what a desktop accounting client would do before
/// it grew a file picker.
Future<void> _exportPdf() async {
  final Uint8List pdf = await const JetReportExporter().toPdf(_report);
  await Printing.sharePdf(bytes: pdf, filename: 'mizan.pdf');
}
