// PdfPainter's decoded-image cache is keyed by byte buffer, not by primitive.
//
// A decoded image depends only on its bytes — `fit`, `opacity` and `bounds` are
// applied at draw time — but `ImagePrimitive`'s value equality covers all of
// them, and `ValueEquality` walks a `List` prop element-wise. Keying the cache
// on the primitive therefore did two bad things at once: every probe hashed
// every byte of the image, and it never hit for a repeated image, so one logo
// down a band decoded once PER ROW on export.
//
// `_embeddedImages` in the same class was already keyed by byte instance; this
// pins `_decoded` to the same rule. CanvasPainter was fixed the same way in
// a9d41d3.
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart'; // JetBoxFit
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/export/pdf_painter.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const PageFormat page =
      PageFormat(width: 200, height: 200, margins: JetEdgeInsets.all(0));

  Future<Uint8List> pngBytes() async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4),
        ui.Paint()..color = const ui.Color(0xFF3366CC));
    final ui.Image img = await rec.endRecording().toImage(4, 4);
    final Uint8List bytes =
        (await img.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
    img.dispose();
    return bytes;
  }

  test('one image down many rows is decoded once, not once per row', () async {
    final Uint8List logo = await pngBytes();
    // The same buffer instance at three different positions — exactly what the
    // renderer emits for one element repeated down a band, since
    // `image_element_renderer` passes `source.bytes` straight through.
    final FrameBuilder b = FrameBuilder(page);
    for (int row = 0; row < 3; row++) {
      b.add(ImagePrimitive(
        bounds: JetRect(x: 0, y: row * 20.0, width: 16, height: 16),
        bytes: logo,
        fit: JetBoxFit.contain,
        elementId: 'logo',
      ));
    }
    final PageFrame frame = b.build();

    final PdfPainter painter = PdfPainter(FontRegistry()..registerDefault());
    await paintFrame(frame, painter);

    expect(painter.debugDecodedImageCount, 1,
        reason: 'three rows share one buffer, so one decode should serve all');
  });

  test('genuinely different images still decode separately', () async {
    final Uint8List a = await pngBytes();
    final Uint8List b2 = Uint8List.fromList(await pngBytes());
    // Distinct buffers: the cache must NOT collapse them, or the guard above
    // would pass for a cache that simply never stores anything.
    final FrameBuilder b = FrameBuilder(page)
      ..add(ImagePrimitive(
          bounds: const JetRect(x: 0, y: 0, width: 16, height: 16),
          bytes: a,
          fit: JetBoxFit.contain))
      ..add(ImagePrimitive(
          bounds: const JetRect(x: 0, y: 40, width: 16, height: 16),
          bytes: b2,
          fit: JetBoxFit.contain));

    final PdfPainter painter = PdfPainter(FontRegistry()..registerDefault());
    await paintFrame(b.build(), painter);

    expect(painter.debugDecodedImageCount, 2);
  });
}
