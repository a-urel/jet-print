// lib/src/rendering/paint/page_rasterizer.dart
/// PNG rasterization of a page frame (spec 012): records the UNCHANGED
/// preview paint path — `paintFrame` -> [CanvasPainter] — into a scaled
/// `dart:ui` picture and encodes it as PNG.
///
/// Zero parallel paint code (Constitution IV): pixel parity with the preview
/// is by construction, because this IS the preview's painter. Joins
/// `canvas_painter.dart` as the second (and only other) declared `dart:ui`
/// file in the rendering seam — the architecture test pins that allowlist.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../frame/page_frame.dart';
import '../text/font_registry.dart';
import 'canvas_painter.dart';
import 'report_painter.dart';

/// Rasterizes one [PageFrame] to PNG bytes at a host-chosen scale.
class PageRasterizer {
  /// Creates the stateless rasterizer.
  const PageRasterizer();

  /// Paints [frame] through the preview's [CanvasPainter] (fonts resolved via
  /// [fonts]) with a `scale` canvas transform and encodes the result as PNG.
  ///
  /// The output pixel dimensions are exactly
  /// `round(page.width x scale)` by `round(page.height x scale)` (SC-006).
  Future<Uint8List> rasterize(
    PageFrame frame,
    FontRegistry fonts, {
    double scale = 1.0,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder)..scale(scale, scale);
    await paintFrame(frame, CanvasPainter(canvas, fonts));
    final ui.Image image = await recorder.endRecording().toImage(
          (frame.page.width * scale).round(),
          (frame.page.height * scale).round(),
        );
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
