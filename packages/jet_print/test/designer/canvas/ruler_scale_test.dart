// RulerScale tick-layout contract (spec 014, C1 / FR-002, FR-008, FR-010,
// SC-002, SC-004). White-box unit test of the pure measurement seam — no widget,
// no Flutter — so the regression-prone math (alignment, adaptive density, "labels
// never overlap") is pinned directly (Principle III).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/design_tunables.dart';
import 'package:jet_print/src/designer/canvas/ruler_metrics.dart';
import 'package:jet_print/src/designer/canvas/ruler_scale.dart';

/// Builds a scale with the production tunables; `formatLabel` echoes the integer
/// so a test can read a major tick's mm value straight back off its label.
RulerScale _scale({
  required double originPx,
  required double pxPerMm,
  double lengthPx = 600,
  double minLabelGapPx = kRulerMinLabelGapPx,
}) =>
    RulerScale(
      originPx: originPx,
      pxPerMm: pxPerMm,
      lengthPx: lengthPx,
      minLabelGapPx: minLabelGapPx,
      stepLadderMm: kRulerStepLadderMm,
      minorDivisions: kRulerMinorDivisions,
      minMinorGapPx: kRulerMinMinorGapPx,
      formatLabel: (int mm) => '$mm',
    );

List<RulerTick> _majors(RulerScale s) =>
    s.ticks.where((RulerTick t) => t.isMajor).toList();

/// The smallest ladder step whose on-screen spacing clears the label gap — the
/// independent oracle for the nice-step rule.
int _expectedStep(double pxPerMm, {double gap = kRulerMinLabelGapPx}) {
  for (final int s in kRulerStepLadderMm) {
    if (s * pxPerMm >= gap) return s;
  }
  return kRulerStepLadderMm.last;
}

void main() {
  // The pxPerMm at the zoom extremes and at 100%, the real range the canvas
  // feeds the scale (viewScale ∈ [kMinZoom, kMaxZoom], pxPerMm = scale·72/25.4).
  final double pxPerMmMin = kMinZoom * kPointsPerMm;
  final double pxPerMmMax = kMaxZoom * kPointsPerMm;
  const double pxPerMm100 = kPointsPerMm;

  group('RulerScale — monotonic & in-bounds (C1.1)', () {
    test(
        'ticks strictly increase and stay within [0, lengthPx] at any zoom/pan',
        () {
      for (final double pxPerMm in <double>[
        pxPerMmMin,
        pxPerMm100,
        pxPerMmMax,
      ]) {
        for (final double origin in <double>[-500, -37, 0, 120, 640]) {
          final RulerScale s =
              _scale(originPx: origin, pxPerMm: pxPerMm, lengthPx: 600);
          final List<RulerTick> ticks = s.ticks;
          for (int i = 0; i < ticks.length; i++) {
            expect(ticks[i].offsetPx, greaterThanOrEqualTo(-1e-6));
            expect(ticks[i].offsetPx, lessThanOrEqualTo(600 + 1e-6));
            if (i > 0) {
              expect(ticks[i].offsetPx, greaterThan(ticks[i - 1].offsetPx),
                  reason: 'ticks must strictly increase');
            }
          }
        }
      }
    });
  });

  group('RulerScale — labelled-gap guarantee (C1.2, SC-004)', () {
    test('consecutive labelled ticks are ≥ minLabelGapPx across the zoom range',
        () {
      for (final double pxPerMm in <double>[
        pxPerMmMin,
        pxPerMm100,
        pxPerMmMax,
      ]) {
        final List<RulerTick> majors =
            _majors(_scale(originPx: 0, pxPerMm: pxPerMm, lengthPx: 900));
        for (int i = 1; i < majors.length; i++) {
          expect(majors[i].offsetPx - majors[i - 1].offsetPx,
              greaterThanOrEqualTo(kRulerMinLabelGapPx - 1e-6),
              reason: 'labels must never crowd below the min gap');
        }
      }
    });
  });

  group('RulerScale — at least one label (C1.3, SC-004)', () {
    test('a non-empty strip always carries ≥ 1 major tick', () {
      for (final double pxPerMm in <double>[
        pxPerMmMin,
        pxPerMm100,
        pxPerMmMax,
      ]) {
        expect(_majors(_scale(originPx: 0, pxPerMm: pxPerMm, lengthPx: 600)),
            isNotEmpty);
      }
    });
  });

  group('RulerScale — nice-step selection (C1.4, FR-010)', () {
    test('the labelled step is the smallest ladder value clearing the gap', () {
      for (final double pxPerMm in <double>[
        pxPerMmMin,
        pxPerMm100,
        pxPerMmMax,
        2.0,
        8.0,
      ]) {
        final List<RulerTick> majors =
            _majors(_scale(originPx: 0, pxPerMm: pxPerMm, lengthPx: 1200));
        final int step =
            int.parse(majors[1].label!) - int.parse(majors[0].label!);
        expect(step, _expectedStep(pxPerMm));
      }
    });

    test('zooming in selects a smaller step; zooming out a larger one', () {
      int stepAt(double pxPerMm) {
        final List<RulerTick> m =
            _majors(_scale(originPx: 0, pxPerMm: pxPerMm, lengthPx: 1200));
        return int.parse(m[1].label!) - int.parse(m[0].label!);
      }

      expect(stepAt(pxPerMmMax), lessThan(stepAt(pxPerMm100)));
      expect(stepAt(pxPerMmMin), greaterThan(stepAt(pxPerMm100)));
    });
  });

  group('RulerScale — alignment exactness (C1.5, SC-002)', () {
    test('a major labelled k mm sits at originPx + k·pxPerMm', () {
      const double origin = 64;
      const double pxPerMm = pxPerMm100;
      for (final RulerTick t in _majors(
          _scale(originPx: origin, pxPerMm: pxPerMm, lengthPx: 800))) {
        final int k = int.parse(t.label!);
        expect(t.offsetPx, closeTo(origin + k * pxPerMm, 1e-6));
      }
    });
  });

  group('RulerScale — subdivisions (C1.6)', () {
    test('minor ticks subdivide the step, carry no label, and clear the floor',
        () {
      final RulerScale s =
          _scale(originPx: 0, pxPerMm: pxPerMm100, lengthPx: 600);
      final List<RulerTick> minors =
          s.ticks.where((RulerTick t) => !t.isMajor).toList();
      expect(minors, isNotEmpty, reason: 'a labelled step should subdivide');
      for (final RulerTick t in minors) {
        expect(t.label, isNull, reason: 'minor ticks never carry a label');
      }
      // No two consecutive ticks (major or minor) are closer than the minor floor.
      for (int i = 1; i < s.ticks.length; i++) {
        expect(s.ticks[i].offsetPx - s.ticks[i - 1].offsetPx,
            greaterThanOrEqualTo(kRulerMinMinorGapPx - 1e-6));
      }
    });
  });

  group('RulerScale — origin off-strip (C1.7, FR-009)', () {
    test(
        'a scrolled-left origin emits only in-bounds ticks with correct labels',
        () {
      // Page scrolled so 0 mm is 200 px to the left of the strip start.
      const double pxPerMm = pxPerMm100;
      const double origin = -200;
      final RulerScale s =
          _scale(originPx: origin, pxPerMm: pxPerMm, lengthPx: 600);
      expect(s.ticks, isNotEmpty);
      for (final RulerTick t in s.ticks) {
        expect(t.offsetPx, greaterThanOrEqualTo(-1e-6));
      }
      // The first visible label is > 0 mm (0 mm is off the left of the strip),
      // and it still satisfies the alignment identity.
      final RulerTick firstMajor = _majors(s).first;
      expect(int.parse(firstMajor.label!), greaterThan(0));
      expect(firstMajor.offsetPx,
          closeTo(origin + int.parse(firstMajor.label!) * pxPerMm, 1e-6));
    });
  });

  group('RulerScale — extreme clamp (C1.8, FR-010)', () {
    test('at max zoom the minor subdivision never refines below ~1 mm', () {
      final RulerScale s =
          _scale(originPx: 0, pxPerMm: pxPerMmMax, lengthPx: 600);
      // Smallest mm-gap between any two adjacent ticks, converted back to mm.
      double minMmGap = double.infinity;
      for (int i = 1; i < s.ticks.length; i++) {
        final double mmGap =
            (s.ticks[i].offsetPx - s.ticks[i - 1].offsetPx) / pxPerMmMax;
        if (mmGap < minMmGap) minMmGap = mmGap;
      }
      expect(minMmGap, greaterThanOrEqualTo(1 - 1e-6),
          reason: 'subdivision must stop at ~1 mm at max zoom');
    });

    test('at min zoom the labelled step never exceeds the largest ladder value',
        () {
      // Force an extreme zoom-out where even 1000 mm would not clear the gap.
      final RulerScale s =
          _scale(originPx: 0, pxPerMm: 0.001, lengthPx: 600, minLabelGapPx: 56);
      final List<RulerTick> majors = _majors(s);
      if (majors.length >= 2) {
        final int step =
            int.parse(majors[1].label!) - int.parse(majors[0].label!);
        expect(step, lessThanOrEqualTo(kRulerStepLadderMm.last));
      }
    });
  });

  group('RulerScale — degenerate inputs', () {
    test('a zero/negative length or non-positive pxPerMm yields no ticks', () {
      expect(
          _scale(originPx: 0, pxPerMm: pxPerMm100, lengthPx: 0).ticks, isEmpty);
      expect(_scale(originPx: 0, pxPerMm: 0, lengthPx: 600).ticks, isEmpty);
    });
  });
}
