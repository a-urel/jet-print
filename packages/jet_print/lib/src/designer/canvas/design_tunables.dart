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
}

/// Grid spacing, in points. When the grid is enabled, moved/resized geometry
/// snaps to integer multiples of this value (FR-011).
const double kGridStep = 8;

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

/// Default size, in points, for a newly created element of each tool type
/// (FR-002). Chosen to be immediately visible and editable at 100% zoom.
const Map<DesignerToolType, JetSize> kDefaultElementSize =
    <DesignerToolType, JetSize>{
  DesignerToolType.text: JetSize(144, 18),
  DesignerToolType.shape: JetSize(96, 48),
  DesignerToolType.image: JetSize(96, 96),
  DesignerToolType.barcode: JetSize(96, 48),
};
