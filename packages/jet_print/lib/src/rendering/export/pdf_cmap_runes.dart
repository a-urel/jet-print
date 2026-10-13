// lib/src/rendering/export/pdf_cmap_runes.dart
/// Which rune a PDF font's ToUnicode CMap carries for each glyph.
///
/// dart_pdf's subsetter allows one CMap entry per glyph (see the font class
/// at the end of `pdf_painter.dart`), so every rune drawn with a glyph is
/// emitted as one shared rune — and that rune is what a viewer extracts for
/// all of them. Choosing it from the font alone, never from the order the
/// document draws runes in, keeps extraction stable: a SPACE that shares its
/// glyph with NO-BREAK SPACE extracts as a space wherever the two appear.
library;

/// Maps each glyph in [charToGlyph] to the rune its CMap entry carries: the
/// lowest code point the font maps to it.
///
/// U+0000 is the exception. dart_pdf makes it CID 0 before anything is drawn,
/// so it keeps whichever glyph it resolves to — glyph 0 (.notdef) when the
/// font does not map it, which is also where every unmapped rune resolves —
/// and no other rune may name that glyph.
Map<int, int> cmapRuneByGlyph(Map<int, int> charToGlyph) {
  final int nullGlyph = charToGlyph[0] ?? 0;
  final Map<int, int> byGlyph = <int, int>{nullGlyph: 0};
  charToGlyph.forEach((int rune, int glyph) {
    if (glyph == nullGlyph) return;
    final int? current = byGlyph[glyph];
    if (current == null || rune < current) byGlyph[glyph] = rune;
  });
  return byGlyph;
}
