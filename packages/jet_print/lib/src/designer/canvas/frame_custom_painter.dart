/// Blits the cached committed frame under the canvas zoom, cheaply.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Paints a pre-recorded [ui.Picture] of the committed design, scaled by
/// [scale]. The picture is recorded once per *model* change (tracked by
/// [revision]); zoom/pan only re-blit it — so dragging an element or zooming
/// never re-runs the element renderers, which is what keeps the 200-element /
/// 60 fps budget (research D5). Pan is applied by the host widget's layout, so
/// this painter only needs the scale.
class FrameCustomPainter extends CustomPainter {
  /// Creates a painter for [picture] at [scale]; [revision] gates repaints.
  const FrameCustomPainter({
    required this.picture,
    required this.scale,
    required this.revision,
  });

  /// The cached committed-frame picture, or null while the first build is
  /// in-flight.
  final ui.Picture? picture;

  /// The zoom factor applied when blitting (1.0 == 100%).
  final double scale;

  /// The model revision the [picture] was recorded at; bumping it forces a
  /// repaint when a new picture replaces the old.
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
