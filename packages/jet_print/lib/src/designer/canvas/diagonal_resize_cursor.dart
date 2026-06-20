/// The mouse cursor each resize handle shows on hover.
library;

import 'package:flutter/services.dart';

import 'native_resize_cursor.dart';
import 'resize_handle.dart';

/// The mouse cursor a [handle] should show on hover.
///
/// Edges use the ordinary axis cursors; corners use the diagonal system cursors
/// (↖↘ / ↗↙). This is ALWAYS a real [SystemMouseCursor], so Flutter's mouse
/// tracker (and the macOS cursor pipeline) stay consistent across every handle —
/// the bug that broke all cursors came from returning a *custom* cursor here.
///
/// On macOS the diagonal system cursors render as a plain arrow (the OS has no
/// public diagonal cursor), so the diagonal look is painted on top natively by
/// [applyNativeCornerCursor], called from the handle's hover callbacks — never by
/// swapping the tracked cursor.
MouseCursor resizeCursorForHandle(ResizeHandle handle) {
  switch (handle) {
    case ResizeHandle.top:
    case ResizeHandle.bottom:
      return SystemMouseCursors.resizeUpDown;
    case ResizeHandle.left:
    case ResizeHandle.right:
      return SystemMouseCursors.resizeLeftRight;
    case ResizeHandle.topLeft:
    case ResizeHandle.bottomRight:
      return SystemMouseCursors.resizeUpLeftDownRight;
    case ResizeHandle.topRight:
    case ResizeHandle.bottomLeft:
      return SystemMouseCursors.resizeUpRightDownLeft;
  }
}

/// On macOS, paints the native diagonal window-resize `NSCursor` for a CORNER
/// [handle], on top of the standard system cursor Flutter already tracks. A no-op
/// for edge handles and on every non-macOS platform (where the diagonal system
/// cursors render correctly on their own).
///
/// Call this from the handle `MouseRegion`'s `onEnter`/`onHover` rather than
/// returning a custom cursor from [resizeCursorForHandle]: the tracked cursor
/// stays a real [SystemMouseCursor] (so the tracker never desyncs and edge
/// cursors keep working), and this just overpaints the diagonal look. macOS does
/// not re-assert the cursor on plain mouse moves, so a single call per enter
/// holds — `onHover` re-applies it after Flutter activates the (arrow) system
/// cursor on entry.
void applyNativeCornerCursor(ResizeHandle handle) {
  switch (handle) {
    case ResizeHandle.topLeft:
    case ResizeHandle.bottomRight:
      setNativeDiagonalResizeCursor(northEastSouthWest: false); // ↖↘
    case ResizeHandle.topRight:
    case ResizeHandle.bottomLeft:
      setNativeDiagonalResizeCursor(northEastSouthWest: true); // ↗↙
    case ResizeHandle.top:
    case ResizeHandle.bottom:
    case ResizeHandle.left:
    case ResizeHandle.right:
      break; // edges keep their (correctly-rendering) system cursor
  }
}
