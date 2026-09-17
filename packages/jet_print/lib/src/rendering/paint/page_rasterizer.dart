// lib/src/rendering/paint/page_rasterizer.dart
/// PNG rasterization of a page frame: records the UNCHANGED
/// preview paint path — `paintFrame` -> [CanvasPainter] — into a scaled
/// `dart:ui` picture and encodes it as PNG.
///
/// Zero parallel paint code: pixel parity with the preview
/// is by construction, because this IS the preview's painter. One of three
/// declared `dart:ui` files in the rendering seam, with `canvas_painter.dart`
/// (the backend) and `record_page_frame.dart` (the recorder/painter/dispose
/// seam this goes through) — the architecture test pins that allowlist.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../frame/page_frame.dart';
import '../text/font_registry.dart';
import 'canvas_painter.dart';
import 'record_page_frame.dart';

/// Rasterizes one [PageFrame] to PNG bytes at a host-chosen scale.
class PageRasterizer {
  /// Creates the stateless rasterizer.
  const PageRasterizer();

  /// Test seam: the picture returned by the last [rasterize] call, so a test
  /// can assert it was disposed. `recordPageFrame` hands ownership of the
  /// picture to its caller, so releasing it is this class's job, not the
  /// seam's. Only assigned when asserts are enabled.
  @visibleForTesting
  static ui.Picture? debugLastPicture;

  /// Paints [frame] through the preview's [CanvasPainter] (fonts resolved via
  /// [fonts]) with a `scale` canvas transform and encodes the result as PNG.
  ///
  /// The output pixel dimensions are exactly
  /// `round(page.width x scale)` by `round(page.height x scale)`.
  Future<Uint8List> rasterize(
    PageFrame frame,
    FontRegistry fonts, {
    double scale = 1.0,
  }) async {
    final ui.Picture picture =
        await recordPageFrame(frame, fonts, scale: scale);
    assert(() {
      debugLastPicture = picture;
      return true;
    }());
    final ui.Image image;
    try {
      image = await picture.toImage(
        (frame.page.width * scale).round(),
        (frame.page.height * scale).round(),
      );
    } finally {
      picture.dispose();
    }
    try {
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('the engine returned no PNG data for the page');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
