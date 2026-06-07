// test/rendering/text/font_metrics_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/text/font_format_exception.dart';
import 'package:jet_print/src/rendering/text/font_metrics.dart';

void main() {
  const FontMetrics m = FontMetrics(
    unitsPerEm: 1000,
    ascent: 1069,
    descent: -293,
    lineGap: 0,
    cmap: <int, int>{0x41: 34},
    advanceWidths: <int>[0, 260, 639],
    defaultAdvance: 0,
  );

  test('maps codepoints to glyphs; unmapped -> 0 (.notdef)', () {
    expect(m.glyphForCodepoint(0x41), 34);
    expect(m.glyphForCodepoint(0x5A), 0);
  });

  test('returns advances; out-of-range -> defaultAdvance', () {
    expect(m.advanceForGlyph(2), 639);
    expect(m.advanceForGlyph(99), 0);
  });

  test('FontFormatException carries a message', () {
    expect(const FontFormatException('bad').toString(), contains('bad'));
  });
}
