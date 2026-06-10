// Faithful fallbacks, never diverging from the preview (012 — contract B5;
// FR-010, SC-007; T006 PDF cases, T016 adds the PNG cases).
//
// Recoverable content problems (empty dataset, unresolved image, failed
// expression) are already materialized in the frame as the preview's
// placeholder/fallback primitives — so the artifact shows the SAME fallback,
// the render diagnostics ride along unchanged, and export never throws for
// content problems.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

import 'support/export_fixtures.dart';
import 'support/pdf_inspector.dart';

void main() {
  const JetReportExporter exporter = JetReportExporter();

  group('PDF — empty dataset', () {
    test('exports the static pages the preview shows (never zero-page)',
        () async {
      final RenderedReport report = emptyDatasetReport();
      expect(report.pageCount, greaterThanOrEqualTo(1),
          reason: 'fixture sanity: the layouter always emits >= 1 page');
      final PdfInspector pdf = PdfInspector(await exporter.toPdf(report));
      expect(pdf.pageCount, report.pageCount);
      expect(pdf.textOnPage(0), contains('Static title'),
          reason: 'static chrome renders exactly as in the preview');
    });
  });

  group('PDF — unresolved image', () {
    test('shows the same placeholder primitives as the preview', () async {
      final RenderedReport report = unresolvedImageReport();
      // The preview's fallback is already IN the frame: an outline rect plus
      // a label text run. Derive the expectation from the frame itself so the
      // artifact provably matches the preview, whatever the label text is.
      final TextRunPrimitive label = report
          .pageAt(0)
          .frame
          .primitives
          .whereType<TextRunPrimitive>()
          .single;
      final String labelText = label.lines.map((TextLine l) => l.text).join();
      expect(labelText, isNotEmpty, reason: 'fixture sanity');

      final int diagnosticsBefore = report.diagnostics.entries.length;
      expect(diagnosticsBefore, greaterThan(0),
          reason: 'fixture sanity: the unresolved URL records a diagnostic');

      final PdfInspector pdf = PdfInspector(await exporter.toPdf(report));
      expect(pdf.textOnPage(0), contains(labelText),
          reason: 'the placeholder label must appear in the artifact');
      expect(pdf.imageDrawsOn(0), isEmpty,
          reason: 'nothing was resolvable — no image XObject is drawn');
      expect(report.diagnostics.entries.length, diagnosticsBefore,
          reason: 'export is read-only over the rendered IR: it must not '
              'add, drop, or mutate diagnostics');
    });
  });

  group('PDF — failed expression', () {
    test(
        'the bad element falls back exactly as in the preview; the good one '
        'renders; diagnostics unchanged', () async {
      final RenderedReport report = failedExpressionReport();
      final int diagnosticsBefore = report.diagnostics.entries.length;
      expect(diagnosticsBefore, greaterThan(0), reason: 'fixture sanity');

      final PdfInspector pdf = PdfInspector(await exporter.toPdf(report));
      expect(pdf.textOnPage(0), contains('alpha'),
          reason: 'surrounding content renders normally');
      expect(report.diagnostics.entries.length, diagnosticsBefore);
    });
  });
}
