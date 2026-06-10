// lib/src/rendering/export/jet_report_exporter.dart
/// The export facade (spec 012): turns the [RenderedReport] the preview
/// displays into shareable artifacts. Headless — bytes in, bytes out; the
/// host owns persistence (FR-009).
library;

import 'dart:typed_data';

import '../engine/rendered_report.dart';
import '../paint/report_painter.dart';
import '../text/font_registry.dart';
import 'pdf_painter.dart';

/// Turns a rendered report into shareable artifacts — the export-side
/// counterpart of `JetReportPreview` (FR-001).
///
/// Stateless and `const`-constructible. Every method consumes the same
/// [RenderedReport] the preview shows: no re-fill, no re-layout, no second
/// render pass. Content problems (unresolved images, failed expressions,
/// empty datasets) never throw — they are already materialized in the frames
/// as the preview's fallback primitives, so the artifact matches the preview
/// (FR-010); only invalid requests throw.
class JetReportExporter {
  /// Creates the stateless exporter.
  const JetReportExporter();

  /// Exports the complete report as a PDF document, pages in order.
  ///
  /// The returned bytes are an in-memory PDF (FR-002) with one page per
  /// [RenderedReport.pageCount] at the template's true physical size in
  /// PostScript points (FR-008), real selectable/searchable text placed at
  /// the pre-measured baselines, and the measuring fonts embedded (FR-004/
  /// 005). All pages are materialized via [RenderedReport.pageAt] regardless
  /// of what the preview has lazily viewed (FR-011).
  ///
  /// Identical rendered inputs produce byte-identical output (FR-007): the
  /// export path reads no clock, randomness, or ambient locale.
  Future<Uint8List> toPdf(RenderedReport report) async {
    // A per-export registry with the bundled default — exactly the registry
    // construction the preview paints with, so measure/draw/embed all share
    // one byte source.
    final FontRegistry fonts = FontRegistry()..registerDefault();
    final PdfPainter painter = PdfPainter(fonts);
    for (int i = 0; i < report.pageCount; i++) {
      await paintFrame(report.pageAt(i).frame, painter);
    }
    return painter.save();
  }
}
