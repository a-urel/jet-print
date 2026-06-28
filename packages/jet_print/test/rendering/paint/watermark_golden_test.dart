@Tags(['golden'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/watermark_primitive.dart';

Future<Uint8List> _solidPng(int w, int h, int argb) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = ui.Color(argb));
  final ui.Image img = await rec.endRecording().toImage(w, h);
  final ByteData data = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagonal DRAFT text watermark behind a white page', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    const PageFormat page =
        PageFormat(width: 200, height: 200, margins: JetEdgeInsets.all(0));
    final FramePrimitive wmPrim = buildWatermarkPrimitive(
        const Watermark(
            text: 'DRAFT',
            opacity: 0.2,
            angleDegrees: -45,
            textStyle: JetTextStyle(fontSize: 56, color: JetColor(0xFF000000))),
        page,
        MetricsTextMeasurer(reg))!;
    final PageFrame frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 200, height: 200),
              fill: JetColor(0xFFFFFFFF)))
          ..add(wmPrim))
        .build();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), reg);
    await paintFrame(frame, painter);
    final ui.Image image = await recorder.endRecording().toImage(200, 200);
    await expectLater(image, matchesGoldenFile('goldens/watermark_text.png'));
  });

  test('image watermark dimmed and centered behind a white page', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    // A small solid red square as the watermark image.
    final Uint8List redPng = await _solidPng(20, 20, 0xFFFF0000);

    const PageFormat page =
        PageFormat(width: 200, height: 200, margins: JetEdgeInsets.all(0));
    final FramePrimitive wmPrim = buildWatermarkPrimitive(
        Watermark(imageBytes: redPng, opacity: 0.2),
        page,
        MetricsTextMeasurer(reg))!;
    final PageFrame frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 200, height: 200),
              fill: JetColor(0xFFFFFFFF)))
          ..add(wmPrim))
        .build();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), reg);
    await paintFrame(frame, painter);
    final ui.Image image = await recorder.endRecording().toImage(200, 200);
    await expectLater(image, matchesGoldenFile('goldens/watermark_image.png'));
  });
}
