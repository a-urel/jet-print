/// The mouse cursor each resize handle shows on hover.
library;

import 'package:flutter/services.dart';

import 'resize_handle.dart';

/// The mouse cursor a [handle] should show on hover.
///
/// Edges use the ordinary axis cursors; corners use the diagonal system cursors
/// (↖↘ / ↗↙). Flutter supports all of these natively on every platform we target
/// — including macOS (since the engine maps the diagonal cursors to the private
/// window-resize `NSCursor`s) — so there is no platform-specific cursor here.
///
/// (Historical note: an earlier custom macOS cursor set the `NSCursor`
/// imperatively via the Objective-C runtime. That bypassed Flutter's cursor
/// pipeline and desynced macOS cursor management, breaking *every* handle cursor;
/// it was removed once Flutter shipped native macOS diagonal-cursor support.)
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
