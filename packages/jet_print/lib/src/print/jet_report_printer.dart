// lib/src/print/jet_report_printer.dart
/// The print seam (spec 012): the ONLY library code touching a platform
/// channel, isolated here behind the swappable [PrintDialogPresenter]
/// abstraction so the rendering core stays platform-agnostic and printing is
/// testable without channels. Nothing in the library may import this seam —
/// it is outermost; the architecture test pins both rules.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../domain/page_format.dart';
import '../rendering/engine/rendered_report.dart';
import '../rendering/export/jet_report_exporter.dart';

/// Presents the system print dialog for [pdfBytes] — the swappable print
/// seam (contract B6).
///
/// [jobName] is the title the OS shows for the job; [pageWidthPt] and
/// [pageHeightPt] are the document's true page size in PostScript points.
/// Returns `true` when the job was handed to the OS and `false` when the
/// user cancelled the dialog. Implementations should throw
/// [PrintUnavailableException] where printing is unsupported.
typedef PrintDialogPresenter = Future<bool> Function(
  Uint8List pdfBytes, {
  required String jobName,
  required double pageWidthPt,
  required double pageHeightPt,
});

/// Printing is not available on this platform (FR-009a).
///
/// Specific and identifiable — never a crash, never a silent no-op. User
/// cancellation is NOT this exception; it is a `false` return from
/// [JetReportPrinter.printReport].
class PrintUnavailableException implements Exception {
  /// Creates the exception with a [message] naming the platform/cause.
  const PrintUnavailableException(this.message);

  /// What is unavailable and why/where.
  final String message;

  @override
  String toString() => 'PrintUnavailableException: $message';
}

/// Prints a rendered report via the operating system's print dialog — the
/// one sanctioned exception to the library's headlessness (FR-009a).
///
/// The job content is exactly the deterministic PDF [JetReportExporter.toPdf]
/// exports: the document is the artifact, so what prints matches the preview
/// page-for-page, whatever paper the user picks in the dialog.
class JetReportPrinter {
  /// Creates a printer. [presenter] substitutes the system print dialog —
  /// inject a fake in tests (no platform channels) or a host implementation;
  /// null means the `package:printing` system dialog.
  const JetReportPrinter({PrintDialogPresenter? presenter})
      : _presenter = presenter;

  final PrintDialogPresenter? _presenter;

  /// Exports [report] to PDF and presents the system print dialog at the
  /// template's true page size.
  ///
  /// [jobName] defaults to the non-empty [RenderedReport.title], then
  /// `'Report'`. Returns `true` when the job was handed to the OS and
  /// `false` when the user cancelled (not an error). Throws
  /// [PrintUnavailableException] where the platform cannot print.
  Future<bool> printReport(RenderedReport report, {String? jobName}) async {
    final Uint8List pdfBytes = await const JetReportExporter().toPdf(report);
    final PageFormat page = report.pageAt(0).frame.page;
    final String name =
        jobName ?? (report.title.isNotEmpty ? report.title : 'Report');
    final PrintDialogPresenter present = _presenter ?? _systemPrintDialog;
    return present(
      pdfBytes,
      jobName: name,
      pageWidthPt: page.width,
      pageHeightPt: page.height,
    );
  }
}

/// The default presenter: `package:printing`'s system dialog.
///
/// `Printing.info()` never throws — unsupported platforms report
/// `canPrint: false`, which becomes a clean [PrintUnavailableException]
/// (research §3). `onLayout` returns the same deterministic bytes whatever
/// paper the user picks: reflowing to the dialog's paper would break WYSIWYG.
Future<bool> _systemPrintDialog(
  Uint8List pdfBytes, {
  required String jobName,
  required double pageWidthPt,
  required double pageHeightPt,
}) async {
  final PrintingInfo info = await Printing.info();
  if (!info.canPrint) {
    throw const PrintUnavailableException(
        'printing is not available on this platform '
        '(the printing plugin reports canPrint: false)');
  }
  return Printing.layoutPdf(
    onLayout: (_) async => pdfBytes,
    name: jobName,
    format: PdfPageFormat(pageWidthPt, pageHeightPt),
    // NEVER dynamic: the plugin's macOS dynamic mode blocks the main thread
    // on a semaphore inside the print operation while waiting for a Dart
    // reply that can only be delivered on that same thread — the app
    // freezes before the dialog opens. We have nothing to re-layout anyway:
    // the exported bytes ARE the artifact whatever paper the dialog picks
    // (contract B6); pinned by default_presenter_channel_test.dart.
    dynamicLayout: false,
  );
}
