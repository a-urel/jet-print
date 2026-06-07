// lib/src/rendering/text/metrics_text_measurer.dart
/// Default [TextMeasurer] (spec 006): measures glyph advances via [FontMetrics],
/// greedily word-wraps while preserving literal whitespace, and lays out lines.
library;

import '../../domain/geometry.dart';
import '../../domain/styles/text_style.dart';
import 'font_metrics.dart';
import 'font_registry.dart';
import 'text_measurer.dart';

/// Measures text using registered font metrics. Deterministic, headless.
class MetricsTextMeasurer implements TextMeasurer {
  /// Creates a measurer backed by [registry].
  MetricsTextMeasurer(this._registry);

  final FontRegistry _registry;

  @override
  MeasuredText measure(String text, JetTextStyle style, {double? maxWidth}) {
    final FontMetrics m = _registry.metricsFor(style.fontFamily,
        weight: style.weight, italic: style.italic);
    final double scale = style.fontSize / m.unitsPerEm;
    final double lineAscent = m.ascent * scale;
    final double lineHeight = (m.ascent - m.descent + m.lineGap) * scale;

    double advanceOf(String s) {
      var w = 0.0;
      for (final int rune in s.runes) {
        final int cp = rune == 0x09 ? 0x20 : rune; // tab -> space
        w += m.advanceForGlyph(m.glyphForCodepoint(cp)) * scale;
      }
      return w;
    }

    final List<TextLine> lines = <TextLine>[];
    void emit(String content) {
      final int i = lines.length;
      lines.add(TextLine(
        text: content,
        width: advanceOf(content),
        top: i * lineHeight,
        baseline: i * lineHeight + lineAscent,
        height: lineHeight,
      ));
    }

    for (final String segment in text.split('\n')) {
      if (maxWidth == null) {
        emit(segment);
      } else {
        for (final String piece in _wrap(segment, maxWidth, advanceOf)) {
          emit(piece);
        }
      }
    }

    var maxW = 0.0;
    for (final TextLine l in lines) {
      if (l.width > maxW) maxW = l.width;
    }
    return MeasuredText(
      lines: lines,
      size: JetSize(maxW, lines.length * lineHeight),
      firstAscent: lineAscent,
      fontFamily: _registry.resolveFamily(style.fontFamily,
          weight: style.weight, italic: style.italic),
    );
  }

  /// Greedy wrap. Tokenizes into alternating non-space/space runs (preserving
  /// every character) and packs tokens until the next would exceed [maxWidth].
  static List<String> _wrap(
      String segment, double maxWidth, double Function(String) advanceOf) {
    if (maxWidth <= 0) return <String>[segment]; // wrapping is meaningless
    final List<String> tokens = _tokenize(segment);
    if (tokens.isEmpty) return <String>[''];
    final List<String> out = <String>[];
    var line = '';
    for (final String token in tokens) {
      if (line.isNotEmpty && advanceOf(line + token) > maxWidth) {
        out.add(line);
        line = token;
      } else {
        line += token;
      }
    }
    out.add(line);
    return out;
  }

  static List<String> _tokenize(String s) {
    final List<String> tokens = <String>[];
    final StringBuffer buf = StringBuffer();
    bool? space;
    for (final int rune in s.runes) {
      final bool isSpace = rune == 0x20 || rune == 0x09;
      if (space != null && isSpace != space) {
        tokens.add(buf.toString());
        buf.clear();
      }
      buf.writeCharCode(rune);
      space = isSpace;
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }
}
