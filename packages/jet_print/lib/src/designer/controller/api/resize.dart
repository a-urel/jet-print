// Element and band resize commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlResize on JetReportDesignerController {
  /// The previewed band-relative bounds of [id] during a live resize, or null.
  /// The overlay draws the selection at this preview while dragging a handle.
  JetRect? previewBoundsFor(String id) =>
      _resizeId == id ? _resizePreview : null;
  /// Begins resizing element [id] by dragging [handle].
  void beginResize(String id, ResizeHandle handle) {
    final ({Band band, ReportElement element})? loc = _locate(id);
    if (loc == null) return;
    _resizeId = id;
    _resizeHandle = handle;
    _resizeStart = loc.element.bounds;
    _resizePreview = loc.element.bounds;
    _activeBandId = loc.band.id;
    _guides = const <SnapGuide>[];
  }
  /// Updates the in-progress resize by a cumulative pointer [delta] (points),
  /// applying the min-size floor, optional snapping (within [threshold] points,
  /// [bypassSnap] to disable), and band clamping; publishes the preview + guides.
  void updateResize(JetOffset delta,
      {double threshold = 0, bool bypassSnap = false}) {
    final String? id = _resizeId;
    final ResizeHandle? handle = _resizeHandle;
    final JetRect? start = _resizeStart;
    if (id == null || handle == null || start == null) return;
    final ({Band band, ReportElement element})? loc = _locate(id);
    if (loc == null) return;

    final bool isLine = loc.element is ShapeElement &&
        (loc.element as ShapeElement).kind == ShapeKind.line;
    final double minW = isLine ? 0 : kMinElementSize;
    final double minH = isLine ? 0 : kMinElementSize;

    JetRect resized =
        resizeRect(start, handle, delta, minWidth: minW, minHeight: minH);
    if (_snapEnabled && !bypassSnap && threshold > 0) {
      final SnapResult result = snapResize(
        resized,
        handle,
        siblings: _siblingBounds(loc.band, id),
        bandBox: _bandBox(loc.band),
        // Decoupled (D3): grid snapping follows the snap tool only — we are
        // inside the `_snapEnabled` guard — while `_gridEnabled` is visibility.
        grid: true,
        gridStep: kGridStep,
        threshold: threshold,
      );
      resized = result.rect;
      _guides = result.guides;
    } else {
      _guides = const <SnapGuide>[];
    }
    // Edge-aware band clamp: a handle stopped at a border pins only its dragged
    // edge and leaves the anchored edge fixed (the move-style `clampToBand` would
    // instead keep the size and shove the far edge out — resizing the wrong side).
    _resizePreview = clampResizeToBand(
      resized,
      handle,
      bandContentWidth(_document.definition.page),
      loc.band.height,
    );
    _frameSerial++;
    _notify();
  }
  /// Commits the in-progress resize as one history entry, or clears state.
  void commitResize() {
    final String? id = _resizeId;
    final JetRect? preview = _resizePreview;
    _resizeId = null;
    _resizeHandle = null;
    _resizeStart = null;
    _resizePreview = null;
    _guides = const <SnapGuide>[];
    _activeBandId = null;
    _frameSerial++;
    bool committed = false;
    if (id != null && preview != null) {
      final ({Band band, ReportElement element})? loc = _locate(id);
      if (loc != null && preview != loc.element.bounds) {
        committed = _commit(ResizeCommand(id: id, bounds: preview));
      }
    }
    // Repaint to drop the resize preview + guides even when the resize committed
    // nothing (a clamped no-op), so no guide stays frozen on the canvas.
    if (!committed) _notify();
  }
  /// Discards an in-progress resize.
  void cancelResize() {
    if (_resizeId == null) return;
    _resizeId = null;
    _resizeHandle = null;
    _resizeStart = null;
    _resizePreview = null;
    _guides = const <SnapGuide>[];
    _activeBandId = null;
    _frameSerial++;
    _notify();
  }
  /// Resizes [id] to [bounds] (clamped to its band) as one undoable step — the
  /// committed form used by numeric Properties editing and tests.
  void resizeTo(String id, JetRect bounds) {
    final ({Band band, ReportElement element})? loc = _locate(id);
    if (loc == null) return;
    final JetRect clamped =
        clampToBand(bounds, loc.band, _document.definition.page);
    if (clamped == loc.element.bounds) return;
    _commit(ResizeCommand(id: id, bounds: clamped));
  }

  // --- Band resize (vertical only) -------------------------------------------
  // A band only has a height; resizing it changes that height. The live
  // interaction previews a height without committing (so the cached frame isn't
  // rebuilt mid-drag), mirroring the element resize lifecycle. The drag's
  // direction-to-height mapping is the caller's concern (a footer grows from its
  // top edge), so [updateBandResize] takes a signed *height* delta.
  /// The previewed height of band [bandId] during a live band resize, or null.
  /// The overlay draws the band at this height while dragging the divider.
  double? bandResizePreviewHeight(String bandId) =>
      _bandResizeId == bandId ? _bandResizePreviewHeight : null;
  /// Begins resizing the band with stable id [bandId] (no history yet). An
  /// unknown id is ignored.
  void beginBandResize(String bandId) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null) return;
    _bandResizeId = bandId;
    _bandResizeStartHeight = band.height;
    _bandResizePreviewHeight = band.height;
  }
  /// Updates the in-progress band resize to a cumulative [heightDelta] (points,
  /// positive grows the band), applying the [kMinBandHeight] floor; publishes the
  /// preview.
  void updateBandResize(double heightDelta) {
    final double? start = _bandResizeStartHeight;
    if (start == null) return;
    final double next = start + heightDelta;
    _bandResizePreviewHeight = next < kMinBandHeight ? kMinBandHeight : next;
    _frameSerial++;
    _notify();
  }
  /// Commits the in-progress band resize as one history entry, or clears the
  /// transient state when nothing changed.
  void commitBandResize() {
    final String? bandId = _bandResizeId;
    final double? preview = _bandResizePreviewHeight;
    _bandResizeId = null;
    _bandResizeStartHeight = null;
    _bandResizePreviewHeight = null;
    _frameSerial++; // the preview frame is gone; re-record the committed one
    bool committed = false;
    if (bandId != null && preview != null) {
      committed = _applyBandHeight(bandId, preview);
    }
    // Repaint to drop the preview even when the resize committed nothing.
    if (!committed) _notify();
  }
  /// Discards an in-progress band resize.
  void cancelBandResize() {
    if (_bandResizeId == null) return;
    _bandResizeId = null;
    _bandResizeStartHeight = null;
    _bandResizePreviewHeight = null;
    _frameSerial++;
    _notify();
  }
}
