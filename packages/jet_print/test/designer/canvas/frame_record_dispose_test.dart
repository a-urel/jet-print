// Texture disposal for the design canvas's record path.
//
// `recordFrame` delegates to `recordPageFrame`; this pins that the canvas
// really does release decoded textures, including when `prepare` throws
// part-way with images already decoded. The canvas re-records on every drag
// preview, so a per-record leak here is the densest in the designer.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jet_print/src/designer/canvas/design_time_frame.dart';
import 'package:jet_print/src/domain/elements/image_source.dart' show JetBoxFit;
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';

const PageFormat _page =
    PageFormat(width: 20, height: 20, margins: JetEdgeInsets.all(0));

Uint8List _validPng() {
  final img.Image image = img.Image(width: 4, height: 2);
  for (int y = 0; y < 2; y++) {
    for (int x = 0; x < 4; x++) {
      image.setPixelRgba(x, y, 32 + 48 * x, 64 + 64 * y, 200, 255);
    }
  }
  return img.encodePng(image);
}

PageFrame _frame(List<Uint8List> images) {
  final FrameBuilder b = FrameBuilder(_page);
  double y = 0;
  for (final Uint8List bytes in images) {
    b.add(ImagePrimitive(
      bounds: JetRect(x: 0, y: y, width: 8, height: 8),
      bytes: bytes,
      fit: JetBoxFit.contain,
    ));
    y += 8;
  }
  return b.build();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(CanvasPainter.debugResetDecodedImageCounters);

  test('recordFrame leaves no decoded texture alive', () async {
    final ui.Picture picture =
        await DesignTimeFrameBuilder().recordFrame(_frame(<Uint8List>[
      _validPng(),
    ]));
    picture.dispose();

    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });

  test('recordFrame releases decoded textures when painting throws', () async {
    // A valid image precedes corrupt bytes, so `prepare` throws with one
    // texture already decoded — without that ordering the test would pass
    // vacuously, having never decoded anything.
    final PageFrame frame = _frame(<Uint8List>[
      _validPng(),
      Uint8List.fromList(<int>[1, 2, 3, 4]),
    ]);

    await expectLater(
        DesignTimeFrameBuilder().recordFrame(frame), throwsA(anything));

    expect(CanvasPainter.debugTotalDecodedImages, greaterThan(0),
        reason: 'a texture must have been decoded before the throw');
    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });
}
