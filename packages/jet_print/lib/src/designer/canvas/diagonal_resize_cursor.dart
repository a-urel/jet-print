/// The mouse cursor for each resize handle, with a macOS workaround for the
/// missing diagonal system cursors.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_resize_cursor.dart';
import 'resize_handle.dart';

/// A diagonal resize cursor that, on macOS, drives the native window-resize
/// `NSCursor` (since macOS has no public diagonal `SystemMouseCursor`).
///
/// Only used on macOS; other platforms get a [SystemMouseCursor] from
/// [resizeCursorForHandle]. Value equality on [northEastSouthWest] keeps the
/// mouse tracker from re-activating the cursor on every rebuild.
@immutable
class _DiagonalResizeCursor extends MouseCursor {
  const _DiagonalResizeCursor({required this.northEastSouthWest});

  /// `true` for ↗↙ (top-right / bottom-left), `false` for ↖↘ (top-left /
  /// bottom-right).
  final bool northEastSouthWest;

  @override
  MouseCursorSession createSession(int device) =>
      _DiagonalResizeCursorSession(this, device);

  @override
  String get debugDescription =>
      'DiagonalResizeCursor(${northEastSouthWest ? 'NESW' : 'NWSE'})';

  @override
  bool operator ==(Object other) =>
      other is _DiagonalResizeCursor &&
      other.northEastSouthWest == northEastSouthWest;

  @override
  int get hashCode => northEastSouthWest.hashCode;
}

class _DiagonalResizeCursorSession extends MouseCursorSession {
  _DiagonalResizeCursorSession(super.cursor, super.device);

  @override
  Future<void> activate() async {
    final _DiagonalResizeCursor c = cursor as _DiagonalResizeCursor;
    // macOS doesn't re-assert the cursor on plain mouse moves (its tracking area
    // has no NSTrackingCursorUpdate), so setting it once per enter holds it.
    setNativeDiagonalResizeCursor(northEastSouthWest: c.northEastSouthWest);
  }

  @override
  void dispose() {}
}

/// The mouse cursor a [handle] should show on hover.
///
/// Edges use the ordinary axis cursors. Corners use the diagonal system cursors
/// (↖↘ / ↗↙) on every platform that has them; on macOS — which lacks public
/// diagonal cursors — they use [_DiagonalResizeCursor], which drives the native
/// window-resize cursor instead.
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
      return _diagonalCursor(northEastSouthWest: false);
    case ResizeHandle.topRight:
    case ResizeHandle.bottomLeft:
      return _diagonalCursor(northEastSouthWest: true);
  }
}

MouseCursor _diagonalCursor({required bool northEastSouthWest}) {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return _DiagonalResizeCursor(northEastSouthWest: northEastSouthWest);
  }
  return northEastSouthWest
      ? SystemMouseCursors.resizeUpRightDownLeft
      : SystemMouseCursors.resizeUpLeftDownRight;
}
