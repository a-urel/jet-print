// lib/src/rendering/text/font_metrics.dart
/// Parsed, scale-free font metrics (spec 006): values are in font units; callers
/// scale by `fontSize / unitsPerEm`.
library;

/// Glyph metrics needed for measurement: advances + a codepoint→glyph map.
class FontMetrics {
  /// Creates font metrics (all linear values in font units).
  const FontMetrics({
    required this.unitsPerEm,
    required this.ascent,
    required this.descent,
    required this.lineGap,
    required Map<int, int> cmap,
    required List<int> advanceWidths,
    required this.defaultAdvance,
  })  : _cmap = cmap,
        _advanceWidths = advanceWidths;

  /// Font design units per em (the scale denominator).
  final int unitsPerEm;

  /// Ascender (font units, typically positive).
  final double ascent;

  /// Descender (font units, typically negative).
  final double descent;

  /// Recommended extra line gap (font units).
  final double lineGap;

  final Map<int, int> _cmap;
  final List<int> _advanceWidths;

  /// Advance used for glyphs outside [advanceWidths].
  final int defaultAdvance;

  /// Glyph id for [codepoint]; 0 (.notdef) when unmapped.
  int glyphForCodepoint(int codepoint) => _cmap[codepoint] ?? 0;

  /// Advance width (font units) for [glyphId]; [defaultAdvance] if out of range.
  int advanceForGlyph(int glyphId) =>
      (glyphId >= 0 && glyphId < _advanceWidths.length)
          ? _advanceWidths[glyphId]
          : defaultAdvance;
}
