// Move / drag commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlMove on JetReportDesignerController {
  /// Translates every selected element by [delta] points (band-relative),
  /// clamping each to its band ∩ page, as one undoable step (FR-008/010/017).
  /// No-op when nothing is selected or the delta is zero.
  void moveBy(JetOffset delta) {
    if (delta.dx == 0 && delta.dy == 0) return;
    final Map<String, JetRect> targets = _clampedMoveTargets(delta);
    if (targets.isEmpty) return;
    _commit(MoveCommand(targets));
  }

  /// Begins a live move of the current selection (no history yet).
  void beginMove() => _moveDelta = const JetOffset(0, 0);

  /// Updates the in-progress move to a cumulative [delta] (points). When a
  /// single element is selected and snapping is on, [threshold] (points) and the
  /// grid/sibling/band candidates pull the delta to an aligned position and
  /// publish guides. [bypassSnap] (Alt/Option) disables snapping for this update.
  void updateMove(JetOffset delta,
      {double threshold = 0, bool bypassSnap = false}) {
    JetOffset effective = delta;
    _guides = const <SnapGuide>[];
    _activeBandId = null;
    final String? single = _document.selection.singleOrNull;
    if (single != null && _snapEnabled && !bypassSnap && threshold > 0) {
      final ({Band band, ReportElement element})? loc = _locate(single);
      if (loc != null) {
        final JetRect b = loc.element.bounds;
        final SnapResult result = snapMove(
          JetRect(
              x: b.x + delta.dx,
              y: b.y + delta.dy,
              width: b.width,
              height: b.height),
          siblings: _siblingBounds(loc.band, single),
          bandBox: _bandBox(loc.band),
          // Grid snapping is governed solely by the snap tool now (D3): we are
          // already inside the `_snapEnabled` guard, so feed the grid candidates
          // unconditionally. `_gridEnabled` controls only the grid's VISIBILITY.
          grid: true,
          gridStep: kGridStep,
          threshold: threshold,
        );
        effective = JetOffset(result.rect.x - b.x, result.rect.y - b.y);
        _guides = result.guides;
        _activeBandId = loc.band.id;
      }
    }
    _moveDelta = effective;
    _frameSerial++;
    _notify();
  }

  /// Commits the in-progress move as a single history entry (FR-017), or clears
  /// the transient state when nothing moved.
  void commitMove() {
    final JetOffset? delta = _moveDelta;
    _moveDelta = null;
    _guides = const <SnapGuide>[];
    _activeBandId = null;
    _frameSerial++; // the drag's preview frame is gone; re-record the committed one
    bool committed = false;
    if (delta != null && (delta.dx != 0 || delta.dy != 0)) {
      final Map<String, JetRect> targets = _clampedMoveTargets(delta);
      if (targets.isNotEmpty) committed = _commit(MoveCommand(targets));
    }
    // Always repaint to drop the drag ghost + snap guides — even when the move
    // was wholly absorbed by clamping (which commits nothing), so the guide
    // never stays frozen on the canvas with no drag in progress.
    if (!committed) _notify();
  }

  /// Discards an in-progress move, restoring the pre-drag view.
  void cancelMove() {
    if (_moveDelta == null) return;
    _moveDelta = null;
    _guides = const <SnapGuide>[];
    _activeBandId = null;
    _frameSerial++;
    _notify();
  }

  // --- Resize ----------------------------------------------------------------
  /// Moves the selection by a precise nudge (no snapping), one undoable step
  /// (FR-016). Arrow keys pass ±1 pt; Shift+arrow ±10 pt.
  void nudge(double dx, double dy) => moveBy(JetOffset(dx, dy));
}
