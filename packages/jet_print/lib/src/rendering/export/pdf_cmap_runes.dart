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
/// Glyph 0 (.notdef) is the exception: it always carries U+0000, which
/// dart_pdf makes CID 0 before anything is drawn and which every unmapped
/// rune resolves alongside. U+0000's own entry in [charToGlyph], if the font
/// has one, is ignored — the caller must make the subsetter agree, by taking
/// that entry out of the font it embeds.
Map<int, int> cmapRuneByGlyph(Map<int, int> charToGlyph) {
  final Map<int, int> byGlyph = <int, int>{0: 0};
  charToGlyph.forEach((int rune, int glyph) {
    if (rune == 0 || glyph == 0) return;
    final int? current = byGlyph[glyph];
    if (current == null || rune < current) byGlyph[glyph] = rune;
  });
  return byGlyph;
}
