// lib/src/rendering/text/underline_metrics.dart
/// The ONE underline geometry source (021 / US1 / research §2).
///
/// Both paint backends draw the underline as an explicit stroked line — never
/// `dart:ui`'s `TextDecoration`, whose placement comes from font tables the
/// PDF backend does not read. Computing offset and thickness here, and only
/// here, makes canvas, PNG preview, and PDF export identical by construction
/// (Constitution IV — the `shapePath` pattern applied to text).
library;

/// Em-fraction underline placement below the baseline. Conventional values
/// most report fonts agree on within a pixel at print DPI; swapping in real
/// TTF `post`-table metrics later changes only this function.
const double _offsetEm = 0.11;

/// Em-fraction underline stroke thickness.
const double _thicknessEm = 0.06;

/// Underline geometry for [fontSize]: the line's [offset] below the glyph
/// baseline and its stroke [thickness], both in points. Each painter strokes
/// the segment at its own per-line aligned `dx` over the measured line width.
({double offset, double thickness}) underlineFor(double fontSize) =>
    (offset: _offsetEm * fontSize, thickness: _thicknessEm * fontSize);
