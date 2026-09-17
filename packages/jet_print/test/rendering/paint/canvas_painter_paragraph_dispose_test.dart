// `ui.Paragraph` disposal.
//
// `drawTextRun` builds one paragraph per laid-out line and draws it. Nothing
// released them, so every record leaked a paragraph per line — denser than the
// decoded-image leak, because every report has text and most have no images.
//
// Each paragraph is released the moment its draw returns, NOT deferred to
// `dispose()` like the decoded images. `Canvas.drawParagraph` has the paragraph
// paint itself into the canvas (`_NativeParagraph._paint`, sky_engine
// painting.dart:8226), so the recording holds its own reference by the time the
// draw returns. That keeps the peak at one live paragraph rather than one per
// line. Releasing too early would not be silent — `drawParagraph` asserts
// `!debugDisposed` — which is what makes the tighter lifetime safe to take.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/record_page_frame.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const PageFormat page =
      PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(0));
  const JetTextStyle style = JetTextStyle(fontSize: 12);

  /// A frame holding a multi-line text run, so the leak is per-line and not
  /// merely per-primitive.
  PageFrame textFrame(FontRegistry reg) {
    final MeasuredText m = MetricsTextMeasurer(reg).measure(
        'Invoice total due on receipt, payable in full', style,
        maxWidth: 60);
    expect(m.lines.length, greaterThan(1),
        reason: 'the fixture must wrap, or this tests one paragraph not many');
    return (FrameBuilder(page)
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 0, y: 0, width: 60, height: 80),
              lines: m.lines,
              style: style,
              fontFamily: reg.resolveFamily(null))))
        .build();
  }

  test('every paragraph is released as its draw returns', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), reg);

    await paintFrame(textFrame(reg), painter);

    final List<ui.Paragraph> built = painter.debugParagraphs.toList();
    expect(built.length, greaterThan(1),
        reason: 'one paragraph per laid-out line');
    // Already released — before endRecording, before dispose().
    expect(built.every((ui.Paragraph p) => p.debugDisposed), isTrue);

    // The recording still completes and rasterizes, which is what proves the
    // release was not premature.
    final ui.Picture picture = rec.endRecording();
    try {
      final ui.Image image = await picture.toImage(200, 100);
      expect(image.width, 200);
      image.dispose();
    } finally {
      picture.dispose();
    }
    painter.dispose();
  });

  test('an empty line builds no paragraph at all', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final MeasuredText m = MetricsTextMeasurer(reg).measure('', style);
    final PageFrame blank = (FrameBuilder(page)
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 0, y: 0, width: 60, height: 80),
              lines: m.lines,
              style: style,
              fontFamily: reg.resolveFamily(null))))
        .build();

    final ui.PictureRecorder rec = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), reg);
    await paintFrame(blank, painter);
    rec.endRecording();

    expect(painter.debugParagraphs, isEmpty);
    painter.dispose();
  });

  /// Counts pixels the frame actually painted (non-transparent), by
  /// rasterizing it through the real record seam.
  Future<int> paintedPixels(PageFrame frame, FontRegistry reg) async {
    final ui.Picture picture = await recordPageFrame(frame, reg, scale: 2.0);
    try {
      final ui.Image image = await picture.toImage(400, 200);
      try {
        final ByteData data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        int painted = 0;
        for (int i = 3; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) != 0) painted++;
        }
        return painted;
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  // The guard that matters on web. The golden suite is macOS-only (see
  // dart_test.yaml), so a CanvasKit-only disposal bug is structurally invisible
  // to it — releasing a paragraph too early would still produce byte-identical
  // goldens on the VM while dropping the glyphs in a browser. This asserts at
  // the raster level and runs on the chrome leg.
  //
  // The blank-text half is the control: without it, "some pixels were painted"
  // could pass for reasons having nothing to do with text.
  test('rasterized text reaches the pixels, and blank text does not', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();

    final MeasuredText empty = MetricsTextMeasurer(reg).measure('', style);
    final PageFrame blank = (FrameBuilder(page)
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 0, y: 0, width: 60, height: 80),
              lines: empty.lines,
              style: style,
              fontFamily: reg.resolveFamily(null))))
        .build();

    expect(await paintedPixels(blank, reg), 0,
        reason: 'a frame with no text must paint nothing, or the assertion '
            'below proves nothing about glyphs');
    expect(await paintedPixels(textFrame(reg), reg), greaterThan(0),
        reason: 'glyphs must survive the paragraph being released');
  });
}
