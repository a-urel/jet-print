// Pure grid-line geometry (spec 015, contract C1). `gridLineOffsets` enumerates
// the snap-coincident lines to draw along one axis of one band, from the band
// origin, as exact multiples of the step — so a drawn line always lands on a
// snap target (true WYSIWYG). This file pins the ENUMERATION contract (C1.1,
// C1.4, C1.5); the adaptive-density cases (C1.2/C1.3) are added in US3.
//
// Imports the pure helper directly (it carries no Flutter/domain import), the
// same way the ruler-scale tests exercise their measurement core.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/design_tunables.dart';
import 'package:jet_print/src/designer/canvas/grid_geometry.dart';

void main() {
  group('gridLineOffsets — line enumeration (C1.1/C1.4/C1.5)', () {
    // A scale generous enough that step·scale clears any minGap, so no
    // coarsening is in play and we observe the raw multiples.
    const double generousScale = 10;
    const double smallGap = 1;

    test('C1.1 ascending multiples of step within [0, extent]', () {
      final List<double> lines = gridLineOffsets(
          100, kGridStep, generousScale, smallGap, kGridMaxCoarsenFactor);

      // Non-empty, strictly ascending, every value an exact multiple of step.
      expect(lines, isNotEmpty);
      for (int i = 1; i < lines.length; i++) {
        expect(lines[i], greaterThan(lines[i - 1]),
            reason: 'offsets must be strictly ascending');
      }
      for (final double o in lines) {
        final double k = o / kGridStep;
        expect(k, closeTo(k.roundToDouble(), 1e-9),
            reason: '$o is not an exact multiple of the step');
      }
      // Starts at the band origin.
      expect(lines.first, 0);
      // Matches the closed-form enumeration 0, step, 2·step, … ≤ 100.
      final List<double> expected = <double>[
        for (int k = 0; k * kGridStep <= 100 + 1e-9; k++) k * kGridStep,
      ];
      expect(lines.length, expected.length);
      for (int i = 0; i < expected.length; i++) {
        expect(lines[i], closeTo(expected[i], 1e-9));
      }
    });

    test('C1.4 last line is the greatest multiple ≤ extent (nothing beyond)',
        () {
      // 100 is not a whole multiple of the 5 mm step (≈14.173 pt).
      final List<double> lines = gridLineOffsets(
          100, kGridStep, generousScale, smallGap, kGridMaxCoarsenFactor);

      expect(lines.last, lessThanOrEqualTo(100));
      // The next multiple would overshoot the extent.
      expect(lines.last + kGridStep, greaterThan(100));
      for (final double o in lines) {
        expect(o, greaterThanOrEqualTo(0));
        expect(o, lessThanOrEqualTo(100));
      }
    });

    test('C1.5 degenerate extent = 0 yields no over-extent/negative lines', () {
      final List<double> lines = gridLineOffsets(
          0, kGridStep, generousScale, smallGap, kGridMaxCoarsenFactor);

      // Either empty or just the origin — never a negative or over-extent line.
      expect(lines.length, lessThanOrEqualTo(1));
      expect(lines.every((double o) => o == 0), isTrue);
    });
  });

  group('gridLineOffsets — adaptive density (C1.2/C1.3)', () {
    test('no coarsening while step·scale clears the floor (f = 1)', () {
      // scale 1 ⇒ step·scale ≈ 14.17 px ≥ 4 px ⇒ raw step.
      final List<double> lines = gridLineOffsets(
          100, kGridStep, 1, kGridMinLineGapPx, kGridMaxCoarsenFactor);
      expect(lines.length, greaterThan(1));
      for (int i = 1; i < lines.length; i++) {
        expect(lines[i] - lines[i - 1], closeTo(kGridStep, 1e-9),
            reason: 'lines stay one step apart when the gap is comfortable');
      }
    });

    test('C1.2 coarsens to step·f when step·scale dips below minGap', () {
      // scale 0.2 ⇒ step·scale ≈ 2.835 px < 4 px ⇒ f = ⌈4 / 2.835⌉ = 2.
      const double scale = 0.2;
      final List<double> lines = gridLineOffsets(
          100, kGridStep, scale, kGridMinLineGapPx, kGridMaxCoarsenFactor);

      expect(lines, isNotEmpty);
      expect(lines.first, 0);
      // Every value is still an exact multiple of the base step (snap-coincident)…
      for (final double o in lines) {
        final double k = o / kGridStep;
        expect(k, closeTo(k.roundToDouble(), 1e-9));
      }
      // …and the effective spacing is 2·step, whose on-screen gap clears minGap.
      for (int i = 1; i < lines.length; i++) {
        final double gap = lines[i] - lines[i - 1];
        expect(gap, closeTo(2 * kGridStep, 1e-9));
        expect(gap * scale, greaterThanOrEqualTo(kGridMinLineGapPx));
      }
    });

    test('C1.3 hides the grid past the coarsening cap (returns [])', () {
      // scale 0.05 ⇒ f = ⌈4 / (14.17·0.05)⌉ = ⌈5.64⌉ = 6 > kGridMaxCoarsenFactor.
      final List<double> lines = gridLineOffsets(
          100, kGridStep, 0.05, kGridMinLineGapPx, kGridMaxCoarsenFactor);
      expect(lines, isEmpty,
          reason: 'never draw lines coarser than '
              '$kGridMaxCoarsenFactor·step — hide instead of smearing to a fill');
    });
  });
}
