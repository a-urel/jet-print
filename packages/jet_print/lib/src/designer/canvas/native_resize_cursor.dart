/// Platform hook for applying macOS's diagonal window-resize `NSCursor`.
///
/// macOS's *public* `NSCursor` set has no diagonal resize cursor, so Flutter's
/// `SystemMouseCursors.resizeUpLeftDownRight` / `resizeUpRightDownLeft` fall back
/// to a plain arrow there. The diagonal cursors do exist as private window-resize
/// cursors; [setNativeDiagonalResizeCursor] reaches them through the Objective-C
/// runtime (see the `_io` implementation). Everywhere else this is a no-op and
/// callers fall back to the system cursors, which render correctly.
///
/// The conditional import keeps `dart:ffi` out of web builds: web has no
/// `dart.library.io`, so it gets the stub.
library;

import 'native_resize_cursor_stub.dart'
    if (dart.library.io) 'native_resize_cursor_io.dart' as platform;

/// Makes the macOS diagonal window-resize `NSCursor` the active cursor.
///
/// [northEastSouthWest] picks ↗↙ (`true`, top-right / bottom-left) versus ↖↘
/// (`false`, top-left / bottom-right). Returns whether the platform applied it —
/// always `false` off macOS (including web), so the caller can fall back to a
/// system cursor.
bool setNativeDiagonalResizeCursor({required bool northEastSouthWest}) =>
    platform.setNativeDiagonalResizeCursor(
        northEastSouthWest: northEastSouthWest);
