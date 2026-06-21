@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/elements/image_source.dart'; // JetBoxFit
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A tiny real PNG so instantiateImageCodec has something to decode.
  Future<Uint8List> pngBytes() async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(
        const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint()..color = const ui.Color(0xFF112233));
    final ui.Image img = await rec.endRecording().toImage(2, 2);
    final Uint8List bytes =
        (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    img.dispose();
    return bytes;
  }

  test('dispose() releases every decoded image texture', () async {
    final Uint8List png = await pngBytes();
    final FontRegistry reg = FontRegistry()..registerDefault();
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), reg);

    final frame = (FrameBuilder(const PageFormat(
            width: 10, height: 10, margins: JetEdgeInsets.all(0)))
          ..add(ImagePrimitive(
              bounds: const JetRect(x: 0, y: 0, width: 10, height: 10),
              bytes: png,
              fit: JetBoxFit.contain)))
        .build();
    await paintFrame(frame, painter);
    rec.endRecording();

    final List<ui.Image> decoded = painter.debugDecodedImages.toList();
    expect(decoded, isNotEmpty);
    expect(decoded.every((ui.Image i) => i.debugDisposed), isFalse);

    painter.dispose();

    expect(decoded.every((ui.Image i) => i.debugDisposed), isTrue);
  });
}
