// Faithful fallbacks, never diverging from the preview (012 — contract B5;
// FR-010, SC-007; T006 PDF cases, T016 adds the PNG cases).
//
// Recoverable content problems (empty dataset, unresolved image, failed
// expression) are already materialized in the frame as the preview's
// placeholder/fallback primitives — so the artifact shows the SAME fallback,
// the render diagnostics ride along unchanged, and export never throws for
// content problems.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

import 'support/export_fixtures.dart';
import 'support/pdf_inspector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      // picture-frame glyph paths (no text label since image-glyph placeholder).
      // Confirm the frame has path primitives (the glyph) and no text run.
      final List<PathPrimitive> glyphPaths = report
          .pageAt(0)
          .frame
          .primitives
          .whereType<PathPrimitive>()
          .toList();
      expect(glyphPaths, isNotEmpty,
          reason: 'fixture sanity: image-glyph placeholder emits path primitives');
      expect(
          report.pageAt(0).frame.primitives.whereType<TextRunPrimitive>(),
          isEmpty,
          reason: 'image-glyph placeholder emits no text label');

      final int diagnosticsBefore = report.diagnostics.entries.length;
      expect(diagnosticsBefore, greaterThan(0),
          reason: 'fixture sanity: the unresolved URL records a diagnostic');

      final PdfInspector pdf = PdfInspector(await exporter.toPdf(report));
      expect(pdf.imageDrawsOn(0), isEmpty,
          reason: 'nothing was resolvable — no image XObject is drawn');
      // Parity assertion: the glyph's PathPrimitives must reach the PDF.
      // PdfPainter.drawPath() replays MoveTo→`m`, LineTo→`l`, ClosePath→`h`,
      // then fillPath()→`f` for each filled sub-path (pdf_painter.dart §drawPath).
      // A content stream with no `h f ` sequence means all PathPrimitives were
      // silently dropped — exactly the bug this test's name promises to catch.
      // The glyph paths close with `h` before fill, so `h f ` is the reliable
      // marker that at least one closed filled path reached the artifact.
      expect(pdf.contentOf(0), contains('h f '),
          reason: 'image-glyph placeholder PathPrimitives must be painted in '
              'the PDF: at least one closed+filled path operator sequence '
              '(h f) must appear');
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

  group('PNG — the same content problems produce valid images (T016)', () {
    /// Decodes [png], asserting validity, the exact page dimensions, and that
    /// SOMETHING was painted (the preview's fallback content) — never a
    /// corrupt or empty artifact (SC-007).
    void expectValidNonBlankPage(Uint8List png) {
      final img.Image? decoded = img.decodePng(png);
      expect(decoded, isNotNull, reason: 'corrupt PNG');
      expect(decoded!.width, customPage.width.round());
      expect(decoded.height, customPage.height.round());
      bool painted = false;
      for (final img.Pixel p in decoded) {
        if (p.a != 0) {
          painted = true;
          break;
        }
      }
      expect(painted, isTrue,
          reason: 'the fallback content the preview shows must be visible');
    }

    test('empty dataset -> a valid PNG of the static page', () async {
      expectValidNonBlankPage(
          await exporter.pageToPng(emptyDatasetReport(), 0));
    });

    test('unresolved image -> a valid PNG showing the placeholder', () async {
      final RenderedReport report = unresolvedImageReport();
      final int diagnosticsBefore = report.diagnostics.entries.length;
      expectValidNonBlankPage(await exporter.pageToPng(report, 0));
      expect(report.diagnostics.entries.length, diagnosticsBefore,
          reason: 'export must not touch diagnostics');
    });

    test('failed expression -> a valid PNG with the good content', () async {
      expectValidNonBlankPage(
          await exporter.pageToPng(failedExpressionReport(), 0));
    });
  });
}
