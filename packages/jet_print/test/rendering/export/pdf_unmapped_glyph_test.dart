// Regression: text whose characters the font has no glyph for.
//
// package:pdf's font subsetter (`TtfWriter.withChars`) assumes every rune in
// a font's ToUnicode CMap owns a DISTINCT glyph. CID 0 is always U+0000, which
// resolves to glyph 0 (.notdef); an unmapped rune resolves to glyph 0 too. The
// second claimant of a glyph then takes "whichever glyph is left" — a crash
// (`Bad state: No element`) when none is, i.e. when the unmapped rune is the
// LAST new rune, and silently the WRONG outline for every later rune when one
// is. The export must instead draw the unmapped rune as .notdef, exactly where
// the engine measured it, and leave every other glyph alone.
@TestOn('vm')
library;

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/text/fonts/default_font_data.dart';
import 'package:pdf/pdf.dart' show TtfParser;

import '../../support/report_builders.dart';
import '../../support/workspace.dart';
import 'support/pdf_inspector.dart';

RenderedReport _render(String text, {JetFontFamily? family}) =>
    const JetReportEngine().renderDefinition(
      oneBandReport(elements: <ReportElement>[
        TextElement(
          id: 't',
          bounds: const JetRect(x: 0, y: 0, width: 400, height: 20),
          text: text,
          style: JetTextStyle(fontFamily: family?.name),
        ),
      ]),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
      options: RenderOptions(
        fonts: <JetFontFamily>[if (family != null) family],
      ),
    );

Future<PdfInspector> _export(String text, {JetFontFamily? family}) async =>
    PdfInspector(
        await const JetReportExporter().toPdf(_render(text, family: family)));

/// The bundled default's source subset (`tool/fonts/NotoSans-subset.ttf`)
/// with one cmap entry added: U+0000 -> the glyph of `A`. Fonts often map
/// U+0000 to a glyph of their own (classically glyph 1, `.null`); pointing it
/// at a VISIBLE glyph that another rune also uses makes both ways that can go
/// wrong observable. Regenerate with fontTools:
///
///     f = TTFont('tool/fonts/NotoSans-subset.ttf')
///     for t in f['cmap'].tables:
///         if t.isUnicode(): t.cmap[0] = f.getBestCmap()[0x41]
///     f.save('test/rendering/export/support/null_mapped_font.ttf')
Uint8List _nullMappedFontBytes() => File('${findWorkspaceRoot().path}'
        '/packages/jet_print/test/rendering/export/support/null_mapped_font.ttf')
    .readAsBytesSync();

/// The one embedded font program (the subset `TtfWriter` wrote).
TtfParser _subsetFont(PdfInspector pdf) {
  final RegExp ref = RegExp(r'/FontFile2\s+(\d+)\s+\d+\s+R');
  final Set<int> serials = <int>{
    for (final PdfRawObject o in pdf.objects.values)
      for (final Match m in ref.allMatches(o.dict)) int.parse(m.group(1)!),
  };
  expect(serials, hasLength(1), reason: 'one font, one embedded program');
  final Uint8List bytes = pdf.objects[serials.single]!.stream!;
  return TtfParser(bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length));
}

/// Every CID the page draws, in order.
List<int> _drawnCids(PdfInspector pdf) => <int>[
      for (final Match m
          in RegExp(r'\[<([0-9A-Fa-f]*)>\]\s*TJ').allMatches(pdf.contentOf(0)))
        for (int i = 0; i + 4 <= m.group(1)!.length; i += 4)
          int.parse(m.group(1)!.substring(i, i + 4), radix: 16),
    ];

/// The outline bytes of glyph [index] in [font].
List<int> _outline(TtfParser font, int index) =>
    font.readGlyph(index).data.toList();

void main() {
  final TtfParser source = TtfParser(kDefaultFontBytes.buffer
      .asByteData(kDefaultFontBytes.offsetInBytes, kDefaultFontBytes.length));

  test('fixture sanity: the default font has no glyph for these runes', () {
    for (final int rune in '∑\u{2603}'.runes) {
      expect(source.charToGlyphIndexMap.containsKey(rune), isFalse,
          reason: 'U+${rune.toRadixString(16)} must be unmapped for these '
              'tests to mean anything');
    }
  });

  for (final String text in <String>[
    '∑',
    'Toplam 125,50 ∑',
    'a \u{2603}',
  ]) {
    test('"$text" (unmapped rune last) exports instead of throwing', () async {
      final PdfInspector pdf = await _export(text);
      expect(pdf.pageCount, 1);
      expect(_drawnCids(pdf), hasLength(text.runes.length),
          reason: 'every rune is still drawn, the unmapped one as .notdef');
    });
  }

  test('the mapped text still extracts around the .notdef', () async {
    final PdfInspector pdf = await _export('Toplam 125,50 ∑');
    // The unmapped rune is drawn with glyph 0, which CID 0 (U+0000) owns, so
    // a viewer extracts it as U+0000; every rune the font CAN draw survives.
    final List<int> toUnicode = pdf.toUnicodeMaps.single;
    final String extracted = String.fromCharCodes(<int>[
      for (final int cid in _drawnCids(pdf)) cid == 0 ? 0xFFFD : toUnicode[cid],
    ]);
    expect(extracted, 'Toplam 125,50 \u{FFFD}');
  });

  test('a tab is drawn as the space the engine measured it as', () async {
    // MetricsTextMeasurer lays U+0009 out as U+0020. The font has no glyph
    // for a tab, so drawing it as itself would put a .notdef box, at .notdef
    // width, where the layout left a space.
    final PdfInspector pdf = await _export('A\tA');
    final List<int> cids = _drawnCids(pdf);
    expect(cids, hasLength(3));
    expect(pdf.toUnicodeMaps.single[cids[1]], 0x20);
  });

  test('the .notdef advances by the width the engine measured', () async {
    final PdfInspector pdf = await _export('∑ab');
    // `/W [0 N 0 R]`: object N lists each CID's advance in 1/1000 em. The
    // engine measures an unmapped rune at glyph 0's advance; a zero width
    // would pull every later glyph on the line left of where it was laid out.
    final Match w = RegExp(r'/W\s*\[\s*0\s+(\d+)\s+0\s+R').firstMatch(
        pdf.objects.values.map((PdfRawObject o) => o.dict).join('\n'))!;
    final List<int> widths = <int>[
      for (final Match m in RegExp(r'-?\d+')
          .allMatches(pdf.objects[int.parse(w.group(1)!)]!.dict))
        int.parse(m.group(0)!),
    ];
    final int notdef = (source.glyphInfoMap[0]!.advanceWidth * 1000).toInt();
    expect(notdef, greaterThan(0), reason: 'fixture sanity');
    expect(widths[_drawnCids(pdf).first], notdef);
  });

  for (final String text in <String>[
    'Toplam ∑ 125,50',
    '∑ab\u{2603}cd',
    'Toplam 125,50 ∑',
  ]) {
    test('"$text": every drawn CID carries its own rune\'s outline', () async {
      final PdfInspector pdf = await _export(text);
      final TtfParser subset = _subsetFont(pdf);
      final List<int> cids = _drawnCids(pdf);
      final List<int> runes = text.runes.toList();
      expect(cids, hasLength(runes.length));
      for (int i = 0; i < runes.length; i++) {
        // The writer emits U+0020 with an empty outline on purpose
        // (`TtfWriter.withChars` special-cases char 32): nothing to compare.
        if (runes[i] == 0x20) continue;
        final int sourceGlyph = source.charToGlyphIndexMap[runes[i]] ?? 0;
        // CIDToGIDMap is /Identity: the subset's glyph index IS the CID.
        expect(
          _outline(subset, cids[i]),
          _outline(source, sourceGlyph),
          reason: 'rune ${i + 1} of "$text" '
              '(U+${runes[i].toRadixString(16)}) must draw the source glyph '
              '$sourceGlyph, not a neighbour\'s outline',
        );
      }
    });
  }

  group('a font that maps U+0000 to a glyph of its own', () {
    final Uint8List bytes = _nullMappedFontBytes();
    final TtfParser nullMapped =
        TtfParser(bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length));
    final JetFontFamily family = JetFontFamily(
      name: 'Null Mapped',
      faces: <JetFontFace>[JetFontFace(bytes: bytes)],
    );
    final int glyphA = nullMapped.charToGlyphIndexMap[0x41]!;

    test('fixture sanity: U+0000 and A share a visible glyph', () {
      expect(nullMapped.charToGlyphIndexMap[0], glyphA);
      expect(glyphA, isNot(0));
      expect(_outline(nullMapped, glyphA), isNot(_outline(nullMapped, 0)));
    });

    test('.notdef stays glyph 0 of the subset, and draws the unmapped rune',
        () async {
      final PdfInspector pdf = await _export('A∑', family: family);
      final TtfParser subset = _subsetFont(pdf);
      // CID 0 is U+0000; the subset puts CID 0's glyph at GID 0, which
      // OpenType reserves for .notdef.
      expect(_outline(subset, 0), _outline(nullMapped, 0));
      expect(_drawnCids(pdf).last, 0, reason: '∑ is drawn as .notdef');
    });

    test('A keeps its own CMap entry, outline and extracted text', () async {
      final PdfInspector pdf = await _export('A∑', family: family);
      final int cidA = _drawnCids(pdf).first;
      expect(cidA, isNot(0), reason: 'A must not share CID 0 with U+0000');
      expect(pdf.toUnicodeMaps.single[cidA], 0x41);
      expect(_outline(_subsetFont(pdf), cidA), _outline(nullMapped, glyphA));
    });
  });
}
