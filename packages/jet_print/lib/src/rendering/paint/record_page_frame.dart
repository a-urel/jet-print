/// The one place a page frame is recorded into a picture.
///
/// Recording is always the same five steps — recorder, painter, `paintFrame`,
/// `endRecording`, release — and the last of them is easy to drop: it must
/// happen after `endRecording`, so it cannot live inside `paintFrame`. Open-coded
/// at four call sites it was performed at exactly one, leaking a GPU texture per
/// decoded image on CanvasKit. It lives here instead, and
/// `test/architecture/canvas_painter_single_construction_test.dart` keeps it here.
library;

import 'dart:ui' as ui;

import '../frame/page_frame.dart';
import '../text/font_registry.dart';
import 'canvas_painter.dart';
import 'report_painter.dart';

/// Builds the paint backend for a recording canvas. Defaults to [CanvasPainter];
/// injectable so tests can observe the backend the seam drives.
typedef PainterFactory = ReportPainter Function(
    ui.Canvas canvas, FontRegistry fonts);

/// Records [frame] into a [ui.Picture] at [scale], resolving fonts and images
/// through [fonts], then releases the painter's resources.
///
/// The returned picture holds its own references and stays usable — and is the
/// caller's to dispose. [newPainter] overrides the backend (tests).
Future<ui.Picture> recordPageFrame(
  PageFrame frame,
  FontRegistry fonts, {
  double scale = 1.0,
  PainterFactory? newPainter,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  if (scale != 1.0) canvas.scale(scale, scale);
  final ReportPainter painter =
      (newPainter ?? CanvasPainter.new)(canvas, fonts);
  try {
    await paintFrame(frame, painter);
    // Returned from inside the `try` so the `finally` still runs AFTER
    // `endRecording` on the success path — the picture must already hold its
    // own references before the backend drops its handles.
    return recorder.endRecording();
  } finally {
    // `prepare` decodes images one primitive at a time, so a throw partway
    // through leaves the earlier handles alive. The thumbnail rail swallows
    // exactly that exception, so without this the leak accrues per failed tile.
    painter.dispose();
  }
}
