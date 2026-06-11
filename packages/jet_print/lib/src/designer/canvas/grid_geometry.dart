/// Pure grid-line geometry for the design canvas's visible alignment grid.
///
/// Like `RulerScale`, it is **Flutter-, domain-, and tunable-free** (the
/// step/gap/cap are injected by the caller) — so the tricky adaptive-density
/// math is unit-testable without a widget (Principle III) and the helper carries
/// no view/render coupling.
///
/// Given one band axis, it enumerates the line positions to draw as exact
/// multiples of the snap step, so every drawn line coincides with a snap
/// candidate (the visible grid and the snap grid are single-sourced — true
/// WYSIWYG). The canvas `_GridPainter` is a thin consumer.
library;

/// The ascending line positions (in points, from the band origin up to and
/// including [extent] where it lands on a multiple) to draw along **one axis of
/// one band**.
///
/// - [extent] — band width (vertical lines) or band height (horizontal lines),
///   in points.
/// - [step] — the snap step (points). Lines fall on `0, step, 2·step, …` —
///   exactly the snap multiples.
/// - [scale] — view pixels per point (the live zoom).
/// - [minGapPx] — the minimum on-screen gap, in device pixels, between lines.
/// - [maxCoarsenFactor] — the largest step multiplier before the grid hides.
///
/// **Adaptive density** (FR-006): with `f = max(1, ⌈minGapPx / (step·scale)⌉)`,
/// the grid coarsens to multiples of `step·f` so the on-screen gap always clears
/// [minGapPx]; once `f > maxCoarsenFactor` it returns `[]` (the grid hides rather
/// than drawing lines coarser than `maxCoarsenFactor·step`), so the page never
/// renders as a solid fill. The result is monotonic ascending, clamped to
/// `[0, extent]`, every value an exact multiple of [step], and deterministic.
List<double> gridLineOffsets(
  double extent,
  double step,
  double scale,
  double minGapPx,
  int maxCoarsenFactor,
) {
  if (step <= 0 || extent < 0) return const <double>[];

  // Coarsen until the on-screen spacing clears the floor; hide past the cap.
  final double onScreen = step * scale;
  int f = 1;
  if (onScreen > 0 && onScreen < minGapPx) {
    f = (minGapPx / onScreen).ceil();
  }
  if (f > maxCoarsenFactor) return const <double>[];

  final double effective = step * f;
  final List<double> offsets = <double>[];
  // A tiny epsilon so the last on-extent line is not dropped by float drift.
  final double limit = extent + effective * 1e-9;
  for (int k = 0; k * effective <= limit; k++) {
    offsets.add(k * effective);
  }
  return offsets;
}
