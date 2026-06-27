/// Centralized behavioral tunables for the interactive design surface.
///
/// These constants capture the decisions in research **D7** (grid/snap/nudge/
/// defaults/zoom) in one place so the canvas, controller, commands, and tests
/// all agree on the same values — there are no scattered magic numbers in the
/// designer seam. Everything here is pure data with no Flutter dependency.
library;

import '../../domain/geometry.dart';

/// The element kinds a user can create from the toolbox (FR-001 / FR-002).
///
/// This is the toolbox→canvas drag payload; each value maps to a default
/// element factory via [kDefaultElementSize].
enum DesignerToolType {
  /// A literal-text element ([TextElement]).
  text,

  /// A rectangle shape element ([ShapeElement]).
  shape,

  /// An image element ([ImageElement]).
  image,

  /// A barcode element ([BarcodeElement]).
  barcode,

  /// A chart element ([ChartElement]).
  chart,
}

/// Grid/snap spacing, in **millimetres** — the unit of record for this decision
/// (spec 015 / D2). Drives both the visible alignment grid and the snap step, so
/// they share one source of truth and align with the mm rulers.
const double kGridStepMm = 5;

/// Grid/snap spacing, in **points**: `kGridStepMm · 72/25.4 ≈ 14.173`. Consumed
/// by `snapping.dart` (snap candidates) and the canvas `_GridPainter` (drawn
/// lines), so a drawn line always lands on a snap target (true WYSIWYG). The
/// `72/25.4` factor mirrors `kPointsPerMm` in `ruler_metrics.dart`; it is inlined
/// here to keep this pure-data file free of any canvas-seam import (D2).
const double kGridStep = kGridStepMm * 72 / 25.4;

/// Minimum on-screen gap, in device pixels, between two drawn grid lines. Below
/// it, `gridLineOffsets` coarsens the step (then hides the grid) so the grid
/// never smears into a solid fill when zoomed out (spec 015 / FR-006 / D4).
const double kGridMinLineGapPx = 4;

/// Maximum coarsening multiplier for the visible grid. Past it (an effective
/// step beyond `kGridMaxCoarsenFactor · kGridStepMm = 20 mm`), the grid HIDES
/// rather than drawing ever-coarser lines (spec 015 / FR-006 / D4).
const int kGridMaxCoarsenFactor = 4;

/// Snap activation distance, expressed in **screen pixels**. The canvas
/// converts it to points using the live zoom so the "magnetism" feels the same
/// at every zoom level (FR-011 / SC-004).
const double kSnapThresholdPx = 6;

/// Fine nudge step (arrow keys), in points (FR-016).
const double kNudgeStep = 1;

/// Coarse nudge step (Shift+arrow), in points (FR-016).
const double kCoarseNudgeStep = 10;

/// Minimum element width/height, in points, enforced on resize (FR-009). A
/// [ShapeKind.line] may collapse the cross-axis below this; see `ResizeCommand`.
const double kMinElementSize = 4;

/// Minimum band height, in points, enforced when resizing a band vertically so a
/// band can never collapse to an ungrabbable sliver.
const double kMinBandHeight = 8;

/// Translation applied to each pasted/duplicated copy so it does not land
/// exactly on its source (FR-015 / D7).
const JetOffset kPasteOffset = JetOffset(8, 8);

/// Smallest allowed zoom factor (1.0 == 100%).
const double kMinZoom = 0.25;

/// Largest allowed zoom factor (1.0 == 100%).
const double kMaxZoom = 4.0;

/// Additive zoom step for the in/out controls (0.1 == 10 percentage points),
/// matching the increment the static top bar used in spec 002.
const double kZoomStep = 0.1;

/// Side length, in screen pixels, of a drawn resize handle (FR-009).
const double kHandleVisualSize = 8;

/// Side length, in screen pixels, of a resize handle's *hit* area. It is larger
/// than [kHandleVisualSize] so tiny elements stay grabbable (FR-009 edge case).
const double kHandleHitSize = 16;

/// Side length, in screen pixels, of a resize handle's *hit* area under TOUCH
/// input — a finger-friendly target (~Apple HIG / Material 44pt). Selected by
/// the selection overlay when the active pointer is touch; the drawn handle
/// stays [kHandleVisualSize], so goldens (which never simulate touch) are
/// unchanged.
const double kHandleHitSizeTouch = 44;

/// Default size, in points, for a newly created element of each tool type
/// (FR-002). Chosen to be immediately visible and editable at 100% zoom.
const Map<DesignerToolType, JetSize> kDefaultElementSize =
    <DesignerToolType, JetSize>{
  DesignerToolType.text: JetSize(144, 18),
  DesignerToolType.shape: JetSize(96, 96),
  DesignerToolType.image: JetSize(96, 96),
  DesignerToolType.barcode: JetSize(96, 48),
  DesignerToolType.chart: JetSize(200, 130),
};

// --- Rulers (spec 014) -------------------------------------------------------
// Fixed chrome along the canvas's top + left edges, calibrated in millimetres
// from the page's physical corner (0,0). Like the grid/snap tunables above,
// these are concrete single values (not ranges) so the pure `RulerScale`'s tick
// thresholds are deterministic and unit-testable (research D3/D8).

/// Strip thickness, in screen pixels, of each ruler (and the blank corner box).
/// Fixed UI chrome (like the scrollbars), so it never scales with zoom; drives
/// the canvas viewport inset when rulers are enabled (research D8).
const double kRulerThickness = 20;

/// Minimum gap, in screen pixels, between two **labelled** ticks. The nice-step
/// ladder picks the smallest step whose on-screen spacing clears this, so labels
/// never crowd or overlap at any zoom (research D3 / SC-004).
const double kRulerMinLabelGapPx = 56;

/// The ascending "nice number" ladder, in millimetres, of candidate **labelled**
/// step intervals. The scale picks the smallest entry whose `step·pxPerMm`
/// clears [kRulerMinLabelGapPx]; the top entry clamps an extreme zoom-out
/// (research D3).
const List<int> kRulerStepLadderMm = <int>[
  1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, //
];

/// How many minor subdivisions a labelled step is divided into (so a 10 mm step
/// shows ticks every 2 mm). Subdivision stops refining once the minor spacing
/// would fall below [kRulerMinMinorGapPx] (research D3).
const int kRulerMinorDivisions = 5;

/// Minimum gap, in screen pixels, between **minor** subdivision ticks. At max
/// zoom this floors subdivision near ~1 mm so minor ticks never smear together
/// (research D3 extreme-zoom clamp).
const double kRulerMinMinorGapPx = 6;
