// PDF structure (012 — contract B1/B2; FR-002/003/004/005/008; T003).
//
// The exported document is a REAL document: every page in order, MediaBox
// equal to the template's PageFormat in PostScript points, text emitted as
// text objects with embedded TTF font programs (selectable/searchable — never
// images of text), and images placed at the same computeImageFit geometry the
// preview paints.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/image_fit.dart';

import 'support/export_fixtures.dart';
import 'support/pdf_inspector.dart';

void main() {
  const JetReportExporter exporter = JetReportExporter();

  group('B2 — page count and order', () {
    test('the document has exactly report.pageCount pages, in page order',
        () async {
      final RenderedReport report = invoiceReport();
      expect(report.pageCount, 2,
          reason: 'fixture sanity: 12 lines -> 2 pages');
      final PdfInspector pdf = PdfInspector(await exporter.toPdf(report));
      expect(pdf.pageCount, report.pageCount);
      expect(pdf.textOnPage(0), contains('Page 1 of 2'),
          reason: 'page order must match the preview');
      expect(pdf.textOnPage(1), contains('Page 2 of 2'));
      expect(pdf.textOnPage(0), contains('Line item 1'));
      expect(pdf.textOnPage(1), contains('Total'),
          reason: 'the trailing bands land on the second page');
    });
  });

  group('B2/FR-008 — MediaBox equals the template PageFormat in points', () {
    test('A4 exports as 595.28 x 841.89 pt', () async {
      final PdfInspector pdf = PdfInspector(
          await exporter.toPdf(textOnlyReport(PageFormat.a4Portrait)));
      final List<double> box = pdf.mediaBoxOf(0);
      expect(box[0], 0);
      expect(box[1], 0);
      expect(box[2], closeTo(595.28, 0.01));
      expect(box[3], closeTo(841.89, 0.01));
    });

    test('Letter exports as 612 x 792 pt', () async {
      final PdfInspector pdf =
          PdfInspector(await exporter.toPdf(textOnlyReport(letterPage)));
      final List<double> box = pdf.mediaBoxOf(0);
      expect(box[2], closeTo(612, 0.01));
      expect(box[3], closeTo(792, 0.01));
    });

    test('a custom 200 x 100 pt sheet passes through exactly', () async {
      final PdfInspector pdf =
          PdfInspector(await exporter.toPdf(textOnlyReport(customPage)));
      final List<double> box = pdf.mediaBoxOf(0);
      expect(box[2], closeTo(200, 0.01));
      expect(box[3], closeTo(100, 0.01));
    });
  });

  group('B2/FR-004/005 — real text with embedded fonts', () {
    test('text is drawn as text objects, not rasterized', () async {
      final PdfInspector pdf =
          PdfInspector(await exporter.toPdf(invoiceReport()));
      expect(pdf.hasTextObjectsOn(0), isTrue);
      expect(pdf.hasTextObjectsOn(1), isTrue);
      expect(pdf.imageDrawsOn(0), isEmpty,
          reason: 'a text-only page must contain no image XObjects '
              '(text rasterized to images would violate FR-004)');
    });

    test('the TTF font program is embedded, once per distinct byte source',
        () async {
      final PdfInspector pdf =
          PdfInspector(await exporter.toPdf(invoiceReport()));
      // The invoice uses Default normal AND bold; the bundled default ships
      // real variant faces (021 follow-up), so those are two distinct byte
      // sources — each embedded exactly once, however many runs use them.
      expect(pdf.embeddedFontProgramCount, 2,
          reason: 'embed each resolved font byte source exactly once per '
              'document (FR-005), never once per run');
    });

    test('a known line-item string is extractable (selectable/searchable)',
        () async {
      final PdfInspector pdf =
          PdfInspector(await exporter.toPdf(invoiceReport()));
      expect(pdf.allText, containsAll(<String>['INV-1042', 'Line item 3']),
          reason: 'ToUnicode CMap decoding must recover the literal text');
    });
  });

  group('B2 — images land at the shared computeImageFit geometry', () {
    test('a contain-fit PNG draws into the preview dst rect', () async {
      final RenderedReport report = imageReport(bytes: tinyPngBytes());
      final ImagePrimitive primitive =
          report.pageAt(0).frame.primitives.whereType<ImagePrimitive>().single;
      // The preview geometry: same primitive bounds, same fit math, 4x2 src.
      final ImageFit fit =
          computeImageFit(primitive.fit, primitive.bounds, 4, 2);
      final PdfInspector pdf = PdfInspector(await exporter.toPdf(report));
      final PdfImageDraw draw = pdf.imageDrawsOn(0).single;
      final double pageHeight = customPage.height;
      expect(draw.width, closeTo(fit.dst.width, 0.01));
      expect(draw.height, closeTo(fit.dst.height, 0.01));
      expect(draw.x, closeTo(fit.dst.x, 0.01));
      expect(draw.y, closeTo(pageHeight - (fit.dst.y + fit.dst.height), 0.01),
          reason: 'top-left frame y maps to bottom-left PDF y per draw call');
    });

    test('a fill-fit JPEG draws into the element bounds exactly', () async {
      final RenderedReport report =
          imageReport(bytes: tinyJpegBytes(), fit: JetBoxFit.fill);
      final ImagePrimitive primitive =
          report.pageAt(0).frame.primitives.whereType<ImagePrimitive>().single;
      final PdfInspector pdf = PdfInspector(await exporter.toPdf(report));
      final PdfImageDraw draw = pdf.imageDrawsOn(0).single;
      expect(draw.width, closeTo(primitive.bounds.width, 0.01));
      expect(draw.height, closeTo(primitive.bounds.height, 0.01));
      expect(draw.x, closeTo(primitive.bounds.x, 0.01));
      expect(
          draw.y,
          closeTo(
              customPage.height -
                  (primitive.bounds.y + primitive.bounds.height),
              0.01));
    });
  });
}
