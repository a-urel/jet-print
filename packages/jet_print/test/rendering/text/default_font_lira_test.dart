// The bundled default font draws the Turkish lira sign (₺, U+20BA) in all four
// faces, so a price printed with the default font is never a tofu box — on the
// canvas, in the preview, or in an exported PDF.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/text/font_metrics.dart';
import 'package:jet_print/src/rendering/text/fonts/default_font_data.dart';
import 'package:jet_print/src/rendering/text/ttf/ttf_metrics.dart';

import '../export/support/pdf_inspector.dart';

const int _lira = 0x20BA;

void main() {
  final Map<String, Uint8List> faces = <String, Uint8List>{
    'Regular': kDefaultFontBytes,
    'Bold': kDefaultFontBoldBytes,
    'Italic': kDefaultFontItalicBytes,
    'Bold Italic': kDefaultFontBoldItalicBytes,
  };

  for (final MapEntry<String, Uint8List> face in faces.entries) {
    test('the ${face.key} face maps ₺ to a real glyph', () {
      final FontMetrics m = parseTtfMetrics(face.value);
      final int glyph = m.glyphForCodepoint(_lira);
      expect(glyph, isNonZero, reason: '₺ must not fall back to .notdef');
      expect(m.advanceForGlyph(glyph), isNot(m.advanceForGlyph(0)),
          reason: 'measured at its own width, not the tofu box width');
      expect(m.advanceForGlyph(glyph), greaterThan(0));
    });
  }

  test('a price with ₺ exports to PDF as text, sign included', () async {
    final RenderedReport report = const JetReportEngine().renderDefinition(
      const ReportDefinition(
        name: 'Fiş',
        page: PageFormat(
            width: 226.77, height: 100, margins: JetEdgeInsets.all(5)),
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'd',
                type: BandType.detail,
                height: 20,
                elements: <ReportElement>[
                  TextElement(
                    id: 'total',
                    bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                    text: 'Toplam 125,50 ₺',
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );
    final PdfInspector pdf =
        PdfInspector(await const JetReportExporter().toPdf(report));
    expect(pdf.textOnPage(0), contains('Toplam 125,50 ₺'));
  });
}
