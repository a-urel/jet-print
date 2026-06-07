import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

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

  test('paints a fixture frame (text + rect + line + image) to a smoke golden',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final MetricsTextMeasurer measurer = MetricsTextMeasurer(reg);
    final MeasuredText m =
        measurer.measure('Invoice', const JetTextStyle(fontSize: 24));
    final Uint8List logo = await _solidPng(10, 10, 0xFF3366CC);

    const PageFormat page =
        PageFormat(width: 120, height: 60, margins: JetEdgeInsets.all(0));
    final PageFrame frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 120, height: 60),
              fill: JetColor(0xFFFFFFFF)))
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 6, y: 8, width: 110, height: 30),
              lines: m.lines,
              style: const JetTextStyle(fontSize: 24),
              fontFamily: reg.resolveFamily(null)))
          ..add(ImagePrimitive(
              bounds: const JetRect(x: 96, y: 6, width: 18, height: 18),
              bytes: logo,
              fit: JetBoxFit.contain))
          ..add(const LinePrimitive(
              bounds: JetRect(x: 6, y: 44, width: 108, height: 0),
              start: JetOffset(6, 44),
              end: JetOffset(114, 44),
              color: JetColor.black,
              strokeWidth: 1)))
        .build();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), reg);
    await paintFrame(frame, painter);
    final ui.Image image = await recorder
        .endRecording()
        .toImage(page.width.toInt(), page.height.toInt());

    await expectLater(image, matchesGoldenFile('goldens/canvas_fixture.png'));
  });
}
