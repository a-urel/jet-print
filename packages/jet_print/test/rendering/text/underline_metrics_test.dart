// underlineFor() — the ONE underline geometry source both painters consume
// (021 / US1 / research §2, Constitution IV). Em-fraction constants: offset
// ≈ 0.11 × fontSize below the baseline, thickness ≈ 0.06 × fontSize.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/text/underline_metrics.dart';

void main() {
  group('underlineFor', () {
    test('returns the em-fraction offset and thickness at 12pt', () {
      final ({double offset, double thickness}) m = underlineFor(12);
      expect(m.offset, closeTo(0.11 * 12, 0.001));
      expect(m.thickness, closeTo(0.06 * 12, 0.001));
    });

    test('returns the em-fraction offset and thickness at 100pt', () {
      final ({double offset, double thickness}) m = underlineFor(100);
      expect(m.offset, closeTo(11, 0.001));
      expect(m.thickness, closeTo(6, 0.001));
    });

    test('scales linearly with font size', () {
      final ({double offset, double thickness}) small = underlineFor(10);
      final ({double offset, double thickness}) large = underlineFor(40);
      expect(large.offset, closeTo(small.offset * 4, 0.0001));
      expect(large.thickness, closeTo(small.thickness * 4, 0.0001));
    });
  });
}
