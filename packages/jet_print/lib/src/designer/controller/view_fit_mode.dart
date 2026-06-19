/// How the designer canvas fits the page into the viewport.
///
/// A fit mode is *sticky*: while it is [width] or [page], the canvas re-fits on
/// every viewport resize. Any manual zoom (the +/- buttons, a typed percentage,
/// a mouse-wheel zoom, or a preset pick) drops back to [none] — a plain
/// percentage. This is transient designer view state; it is not part of the
/// report model or the undo/redo history.
enum JetViewFitMode {
  /// Manual zoom: the scale is whatever the user last set.
  none,

  /// The page width fills the viewport (re-fit on resize).
  width,

  /// The whole page (width and height) fits the viewport (re-fit on resize).
  page,
}
