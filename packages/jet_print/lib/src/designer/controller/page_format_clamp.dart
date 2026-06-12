/// Input-conditioning for page edits: corrects a [PageFormat] to a usable page
/// rather than rejecting it (FR-009 / SC-006).
library;

import '../../domain/geometry.dart';
import '../../domain/page_format.dart';

/// The smallest a page side (width or height) may be, in points. A custom
/// dimension at or below this is pulled up so no page is ever zero/negative.
const double kMinPageSide = 1.0;

/// The smallest content extent (page side minus the two margins on that axis)
/// that must remain after clamping, in points — the guarantee that every
/// produced page keeps a positive area to lay content into.
const double kMinContentExtent = 1.0;

/// Returns [format] corrected to a usable page: each side is at least
/// [kMinPageSide], and on each axis the two margins leave at least
/// [kMinContentExtent] of content.
///
/// Negative margins are floored to zero; a margin pair that would consume the
/// page is scaled down proportionally to the largest sum that still leaves
/// [kMinContentExtent] of content. The function is **idempotent** — clamping an
/// already-valid page returns it unchanged (the same instance), so it composes
/// cleanly with the controller's no-op detection.
PageFormat clampPageFormat(PageFormat format) {
  final double width =
      format.width < kMinPageSide ? kMinPageSide : format.width;
  final double height =
      format.height < kMinPageSide ? kMinPageSide : format.height;
  final JetEdgeInsets m = format.margins;
  final ({double near, double far}) h =
      _fitPair(m.left, m.right, width - kMinContentExtent);
  final ({double near, double far}) v =
      _fitPair(m.top, m.bottom, height - kMinContentExtent);
  final PageFormat clamped = PageFormat(
    width: width,
    height: height,
    margins:
        JetEdgeInsets(left: h.near, top: v.near, right: h.far, bottom: v.far),
  );
  // Preserve identity (and thus the controller's no-op path) for a valid page.
  return clamped == format ? format : clamped;
}

/// Floors a margin pair at zero, then scales it down proportionally if its sum
/// exceeds [maxSum] (always ≥ 0), so the pair never consumes more than the
/// content budget while keeping the two sides' relative weighting.
({double near, double far}) _fitPair(double near, double far, double maxSum) {
  final double a = near < 0 ? 0 : near;
  final double b = far < 0 ? 0 : far;
  final double sum = a + b;
  if (sum <= maxSum) return (near: a, far: b);
  if (sum == 0) return (near: 0, far: 0);
  final double factor = maxSum / sum;
  return (near: a * factor, far: b * factor);
}
