// Which rune a PDF font's ToUnicode CMap carries for each glyph.
//
// dart_pdf's subsetter needs one CMap entry per glyph (see
// `pdf_cmap_runes.dart`), so runes that share a glyph must share an entry.
// Which rune that entry names decides what a viewer extracts for all of them;
// it must not depend on which rune the document happened to draw first.
//
// No font in this repository maps two code points to one glyph, so the rule
// is pinned here on synthetic cmaps; `pdf_unmapped_glyph_test.dart` covers
// the drawing path end to end.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/export/pdf_cmap_runes.dart';

void main() {
  test('aliases of one glyph share its lowest code point, in any order', () {
    // NBSP listed before SPACE, as a cmap walk might yield them.
    expect(
      cmapRuneByGlyph(<int, int>{0xA0: 3, 0x20: 3, 0x41: 4}),
      <int, int>{0: 0, 3: 0x20, 4: 0x41},
    );
  });

  test('U+0000 owns glyph 0 when the font does not map it', () {
    expect(cmapRuneByGlyph(<int, int>{0x41: 4})[0], 0);
  });

  test('U+0000 keeps the glyph the font maps it to', () {
    // dart_pdf makes U+0000 CID 0 before anything is drawn, so whatever
    // glyph it resolves to is taken; nothing else may name that glyph.
    final Map<int, int> byGlyph =
        cmapRuneByGlyph(<int, int>{0x00: 1, 0x0D: 1, 0x41: 2});
    expect(byGlyph, <int, int>{1: 0, 2: 0x41});
  });
}
