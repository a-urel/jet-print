// A glyph reachable only through a font's supplementary-plane cmap subtable
// (format 12) must export as itself.
//
// PDF export rewrites every character whose glyph the font lacks to .notdef
// (see pdf_unmapped_glyph_test.dart). It must decide "lacks" from the cmap
// dart_pdf embeds from, which reads format 12, and not from a reader that
// stops at the BMP: otherwise an emoji or historic-script glyph the font does
// carry would be drawn as a box.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../../support/supplementary_font_data.dart';
import 'support/pdf_inspector.dart';

void main() {
  test('a glyph reachable only through a format-12 cmap is kept', () async {
    // U+1F600 maps to the glyph of 'A' in this font, and only through its
    // supplementary-plane cmap subtable.
    final RenderedReport report = const JetReportEngine().renderDefinition(
      const ReportDefinition(
        name: 'supplementary',
        page:
            PageFormat(width: 300, height: 200, margins: JetEdgeInsets.all(10)),
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
                    id: 't',
                    bounds: JetRect(x: 0, y: 0, width: 280, height: 16),
                    text: '\u{1F600}x',
                    style: JetTextStyle(fontFamily: 'Supplementary'),
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
      options: RenderOptions(
        fonts: <JetFontFamily>[
          JetFontFamily(
            name: 'Supplementary',
            faces: <JetFontFace>[
              JetFontFace(bytes: kSupplementaryFixtureFontBytes),
            ],
          ),
        ],
      ),
    );
    final Uint8List bytes = await const JetReportExporter().toPdf(report);
    final PdfInspector pdf = PdfInspector(bytes);

    // dart_pdf writes each shown string as `[<hex>] TJ`, 4 hex digits a CID.
    final String hex = RegExp(r'\[<([0-9A-Fa-f]+)>\]\s*TJ')
        .firstMatch(pdf.contentOf(0))!
        .group(1)!;
    final List<String> cids = <String>[
      for (int i = 0; i < hex.length; i += 4) hex.substring(i, i + 4),
    ];
    expect(cids, hasLength(2));
    expect(cids[0], isNot('0000'),
        reason: 'CID 0 is .notdef; the font does have this glyph');
  });
}
