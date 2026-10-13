// Regression: a character the font has no glyph for broke PDF export.
//
// dart_pdf gives each character its own glyph slot, and the slot for the
// .notdef glyph (0) is already taken by U+0000. A second character that also
// resolved to glyph 0 made its subsetter reach for "the first remaining
// glyph": when that character was the last one placed the list was empty and
// export threw `Bad state: No element`; otherwise the PDF quietly drew some
// other glyph in its place. Such a character now exports as the .notdef box
// the engine measured it as.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../../support/supplementary_font_data.dart';
import 'support/pdf_inspector.dart';

/// One text element per entry of [texts], in the bundled default font, which
/// has no glyph for ∑ (U+2211) or ✓ (U+2713) — or in [fontFamily], registered
/// from [fonts].
Future<PdfInspector> _export(
  List<String> texts, {
  String? fontFamily,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) async {
  final RenderedReport report = const JetReportEngine().renderDefinition(
    ReportDefinition(
      name: 'unmapped',
      page: const PageFormat(
          width: 300, height: 200, margins: JetEdgeInsets.all(10)),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'd',
              type: BandType.detail,
              height: 20.0 * texts.length,
              elements: <ReportElement>[
                for (int i = 0; i < texts.length; i++)
                  TextElement(
                    id: 't$i',
                    bounds: JetRect(x: 0, y: 20.0 * i, width: 280, height: 16),
                    text: texts[i],
                    style: JetTextStyle(fontFamily: fontFamily),
                  ),
              ],
            )),
          ],
        ),
      ),
    ),
    JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    options: RenderOptions(fonts: fonts),
  );
  final Uint8List bytes = await const JetReportExporter().toPdf(report);
  return PdfInspector(bytes);
}

/// Every string shown on page 0 (dart_pdf writes `[<hex>] TJ`), split into
/// 4-digit CIDs, in paint order.
List<List<String>> _shownCids(PdfInspector pdf) => <List<String>>[
      for (final Match m
          in RegExp(r'\[<([0-9A-Fa-f]+)>\]\s*TJ').allMatches(pdf.contentOf(0)))
        <String>[
          for (int i = 0; i < m.group(1)!.length; i += 4)
            m.group(1)!.substring(i, i + 4),
        ],
    ];

void main() {
  test('text ending in an unmapped character exports', () async {
    final PdfInspector pdf = await _export(<String>['a ∑']);
    expect(pdf.pageCount, 1);
  });

  test('text that is only unmapped characters exports', () async {
    final PdfInspector pdf = await _export(<String>['∑', '✓✓']);
    expect(pdf.pageCount, 1);
  });

  test('an unmapped character is drawn as .notdef, not as another glyph',
      () async {
    final PdfInspector pdf = await _export(<String>['a∑b']);
    final List<String> cids = _shownCids(pdf).single;
    expect(cids, hasLength(3));
    expect(cids[1], '0000',
        reason: 'CID 0 is the .notdef slot; any other CID borrows a glyph '
            'that belongs to a different character');
    expect(cids[0], isNot('0000'));
    expect(cids[2], isNot('0000'));
    expect(cids[0], isNot(cids[2]));
  });

  test('the mapped text around it is drawn exactly as without it', () async {
    // The second line is the first with ∑ removed (its two spaces kept).
    final PdfInspector pdf =
        await _export(<String>['Toplam ∑ 125,50', 'Toplam  125,50']);
    final List<List<String>> shown = _shownCids(pdf);
    expect(shown, hasLength(2));
    expect(shown[0][7], '0000');
    expect(<String>[...shown[0]]..removeAt(7), shown[1]);
    expect(pdf.textOnPage(0), contains('Toplam  125,50'),
        reason: 'a line without unmapped characters still extracts');
  });

  test('a tab is drawn as the space the layout measured it as', () async {
    final PdfInspector pdf = await _export(<String>['a\tb', 'a b']);
    final List<List<String>> shown = _shownCids(pdf);
    expect(shown, hasLength(2));
    expect(shown[0], shown[1],
        reason: 'the measurer treats U+0009 as U+0020; the PDF must too');
  });

  test('a glyph reachable only through a format-12 cmap is kept', () async {
    // U+1F600 maps to the glyph of 'A' in this font, and only through its
    // supplementary-plane cmap subtable. dart_pdf embeds that glyph; it must
    // not be rewritten to .notdef because the engine's own cmap reader does
    // not see past the BMP.
    final PdfInspector pdf = await _export(
      <String>['\u{1F600}x'],
      fontFamily: 'Supplementary',
      fonts: <JetFontFamily>[
        JetFontFamily(
          name: 'Supplementary',
          faces: <JetFontFace>[
            JetFontFace(bytes: kSupplementaryFixtureFontBytes),
          ],
        ),
      ],
    );
    final List<String> cids = _shownCids(pdf).single;
    expect(cids, hasLength(2));
    expect(cids[0], isNot('0000'));
  });
}
