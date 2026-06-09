/// The eight resize-handle positions and the geometry of resizing by one.
///
/// A leaf module (pure geometry, no Flutter, no controller) so both the
/// selection overlay and the resize command/controller can share it without an
/// import cycle.
library;

import '../../domain/geometry.dart';

/// The eight resize-handle positions around an element's bounding box.
enum ResizeHandle {
  /// Top-left corner.
  topLeft,

  /// Top edge midpoint.
  top,

  /// Top-right corner.
  topRight,

  /// Right edge midpoint.
  right,

  /// Bottom-right corner.
  bottomRight,

  /// Bottom edge midpoint.
  bottom,

  /// Bottom-left corner.
  bottomLeft,

  /// Left edge midpoint.
  left,
}

/// Which edges a handle drag moves.
extension ResizeHandleEdges on ResizeHandle {
  /// Whether dragging this handle moves the left edge.
  bool get movesLeft =>
      this == ResizeHandle.topLeft ||
      this == ResizeHandle.left ||
      this == ResizeHandle.bottomLeft;

  /// Whether dragging this handle moves the right edge.
  bool get movesRight =>
      this == ResizeHandle.topRight ||
      this == ResizeHandle.right ||
      this == ResizeHandle.bottomRight;

  /// Whether dragging this handle moves the top edge.
  bool get movesTop =>
      this == ResizeHandle.topLeft ||
      this == ResizeHandle.top ||
      this == ResizeHandle.topRight;

  /// Whether dragging this handle moves the bottom edge.
  bool get movesBottom =>
      this == ResizeHandle.bottomLeft ||
      this == ResizeHandle.bottom ||
      this == ResizeHandle.bottomRight;
}

/// Applies a pointer [delta] (points) to [start] by dragging [handle], then
/// enforces a minimum size of [minWidth] × [minHeight] on the dragged axes.
///
/// Only the edges the handle controls move; the opposite edges stay put. If a
/// drag would shrink or invert an edge past the minimum, that edge is pinned so
/// the box keeps at least the minimum extent (FR-009). Band/page containment is
/// applied separately by the controller (`clampToBand`). The minimum is
/// parameterized so a [ShapeKind.line] can collapse one axis to 0.
JetRect resizeRect(
  JetRect start,
  ResizeHandle handle,
  JetOffset delta, {
  double minWidth = 4,
  double minHeight = 4,
}) {
  double left = start.x;
  double right = start.x + start.width;
  double top = start.y;
  double bottom = start.y + start.height;

  if (handle.movesLeft) {
    left = start.x + delta.dx;
    if (left > right - minWidth) left = right - minWidth;
  }
  if (handle.movesRight) {
    right = start.x + start.width + delta.dx;
    if (right < left + minWidth) right = left + minWidth;
  }
  if (handle.movesTop) {
    top = start.y + delta.dy;
    if (top > bottom - minHeight) top = bottom - minHeight;
  }
  if (handle.movesBottom) {
    bottom = start.y + start.height + delta.dy;
    if (bottom < top + minHeight) bottom = top + minHeight;
  }

  return JetRect(x: left, y: top, width: right - left, height: bottom - top);
}
