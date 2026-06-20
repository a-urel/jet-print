/// Non-`dart:io` (e.g. web) fallback: there is no native cursor to drive, so the
/// caller uses the system diagonal cursors instead. See [native_resize_cursor].
library;

/// Always returns `false`: no native cursor is applied off `dart:io` platforms.
bool setNativeDiagonalResizeCursor({required bool northEastSouthWest}) => false;
