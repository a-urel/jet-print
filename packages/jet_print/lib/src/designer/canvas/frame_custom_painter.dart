/// Blits the cached committed frame under the canvas zoom, cheaply.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Paints a pre-recorded [ui.Picture] of the design, scaled by [scale].
///
/// This painter only ever *blits*: zoom and pan re-blit the same picture and
/// never re-run the element renderers, which is what keeps the 200-element /
/// 60 fps budget. Pan is applied by the host widget's layout, so this painter
/// only needs the scale.
///
/// A drag is NOT in that set. `design_canvas.dart` re-records on any change to
/// `controller.frameVersion` (= `revision + _frameSerial`), and `updateMove` /
/// `updateResize` bump `_frameSerial` on every pointer update — so a live drag
/// re-runs the renderers per frame, off the build path, and the budget is what
/// makes that affordable rather than what avoids it.
class FrameCustomPainter extends CustomPainter {
  /// Creates a painter for [picture] at [scale]; [revision] gates repaints.
  const FrameCustomPainter({
    required this.picture,
    required this.scale,
    required this.revision,
  });

  /// The cached frame picture — committed, or a live drag preview — or null
  /// while the first build is in-flight.
  final ui.Picture? picture;

  /// The zoom factor applied when blitting (1.0 == 100%).
  final double scale;

  /// An opaque identity for [picture]; bumping it forces a repaint when a new
  /// picture replaces the old. Each consumer supplies whatever changes when its
  /// picture does — the canvas passes `frameVersion`, the preview and the
  /// thumbnail rail pass the page index. Not a model revision.
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Picture? recorded = picture;
    if (recorded == null) return;
    canvas
      ..save()
      ..scale(scale)
      ..drawPicture(recorded)
      ..restore();
  }

  @override
  bool shouldRepaint(FrameCustomPainter oldDelegate) =>
      oldDelegate.picture != picture ||
      oldDelegate.scale != scale ||
      oldDelegate.revision != revision;
}
