// Viewport (zoom / pan / fit / toggles) commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlView on JetReportDesignerController {
  /// Shows or hides the alignment grid (visibility only; does not affect
  /// snapping). A no-op when [value] already matches.
  void setGridEnabled(bool value) {
    if (_gridEnabled == value) return;
    _gridEnabled = value;
    _notify();
  }

  /// Toggles all snapping (grid + sibling + band).
  void setSnapEnabled(bool value) {
    if (_snapEnabled == value) return;
    _snapEnabled = value;
    _notify();
  }

  /// Shows or hides the rulers. A no-op when [value] already matches (so the
  /// toggle never churns listeners); otherwise notifies.
  void setRulersEnabled(bool value) {
    if (_rulersEnabled == value) return;
    _rulersEnabled = value;
    _notify();
  }

  /// Sets the zoom [scale] (clamped) and [pan] together. Mode-agnostic on
  /// purpose: the canvas applies a computed fit through here without clearing
  /// the active fit mode.
  void setView(double scale, JetOffset pan) {
    final double clamped =
        scale < kMinZoom ? kMinZoom : (scale > kMaxZoom ? kMaxZoom : scale);
    if (clamped == _viewScale && pan == _viewPan) return;
    _viewScale = clamped;
    _viewPan = pan;
    _notify();
  }

  /// Sets just the zoom factor (keeping the current pan). Mode-agnostic.
  void setViewScale(double scale) => setView(scale, _viewPan);

  /// Sets just the pan offset (keeping the current zoom).
  void setViewPan(JetOffset pan) => setView(_viewScale, pan);

  /// Zooms in one step (×1.25); manual zoom, so the fit mode is cleared.
  void zoomIn() => _manualZoom(() => setViewScale(_viewScale * 1.25));

  /// Zooms out one step (÷1.25); manual zoom, so the fit mode is cleared.
  void zoomOut() => _manualZoom(() => setViewScale(_viewScale / 1.25));

  /// Sets the zoom to [percent] % (e.g. 130 → 1.30), clamped; clears the fit
  /// mode. Used by the editable zoom field and the preset menu rows.
  void setZoomPercent(double percent) =>
      _manualZoom(() => setViewScale(percent / 100));

  /// Multiplies the zoom by [factor] (mouse-wheel zoom); clears the fit mode.
  void zoomBy(double factor) =>
      _manualZoom(() => setViewScale(_viewScale * factor));

  /// Selects a sticky fit [mode] and requests a re-fit (fulfilled by the
  /// canvas, which owns the viewport).
  void setViewFitMode(JetViewFitMode mode) {
    _viewFitMode = mode;
    _fitRequest++;
    _notify();
  }

  /// Back-compat alias: fit the page to the viewport width.
  void fitToView() => setViewFitMode(JetViewFitMode.width);

  // --- History ---------------------------------------------------------------
}
