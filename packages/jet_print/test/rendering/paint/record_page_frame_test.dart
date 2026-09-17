// The shared record-then-release sequence.
//
// Every on-screen consumer (design canvas, preview, thumbnail rail, PNG
// rasterizer) records a frame the same way: make a recorder, make a painter,
// `paintFrame`, `endRecording`, then release the painter's decoded textures.
// That last step was open-coded at four sites and performed at exactly one, so
// the sequence now lives in `recordPageFrame` and no site can drop it.
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart'; // JetBoxFit
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/record_page_frame.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const PageFormat page =
      PageFormat(width: 10, height: 10, margins: JetEdgeInsets.all(0));

  /// A tiny real PNG so `instantiateImageCodec` has something to decode.
  Future<Uint8List> pngBytes() async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2),
        ui.Paint()..color = const ui.Color(0xFF112233));
    final ui.Image img = await rec.endRecording().toImage(2, 2);
    final Uint8List bytes =
        (await img.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
    img.dispose();
    return bytes;
  }

  Future<PageFrame> imageFrame() async => (FrameBuilder(page)
        ..add(ImagePrimitive(
            bounds: const JetRect(x: 0, y: 0, width: 10, height: 10),
            bytes: await pngBytes(),
            fit: JetBoxFit.contain)))
      .build();

  test('releases the painter decoded textures once the picture is recorded',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    _CapturingPainter? spy;
    final ui.Picture picture = await recordPageFrame(
      await imageFrame(),
      reg,
      newPainter: (ui.Canvas canvas, FontRegistry fonts) =>
          spy = _CapturingPainter(canvas, fonts),
    );

    // `CanvasPainter.dispose` clears its own map, so the handles are captured
    // on the way through; asserting on the emptied map afterwards would pass
    // whether or not anything was ever decoded.
    final List<ui.Image> decoded = spy!.captured;
    expect(decoded, isNotEmpty,
        reason: 'the frame must actually decode an image for this to mean '
            'anything');
    expect(decoded.every((ui.Image i) => i.debugDisposed), isTrue);
    picture.dispose();
  });

  test('returns a usable picture (disposal happens after endRecording)',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final ui.Picture picture = await recordPageFrame(await imageFrame(), reg);
    try {
      // The picture holds its own references, so it is still rasterizable
      // after the painter released its handles.
      final ui.Image image = await picture.toImage(10, 10);
      expect(image.width, 10);
      image.dispose();
    } finally {
      picture.dispose();
    }
  });

  test('scale is applied to the recording canvas', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    // A black rect filling the 10x10 page. Recorded at scale 2 it must cover a
    // 20x20 raster; at scale 1 everything past 10pt would still be blank, so
    // the pixel at (15, 15) is what distinguishes the two.
    final PageFrame frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
              fill: JetColor.black)))
        .build();
    final ui.Picture picture = await recordPageFrame(frame, reg, scale: 2.0);
    try {
      final ui.Image image = await picture.toImage(20, 20);
      final ByteData pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      // RGBA at (15, 15): opaque alpha means the scaled rect reached it.
      final int alpha = pixels.getUint8((15 * 20 + 15) * 4 + 3);
      expect(alpha, 255);
      image.dispose();
    } finally {
      picture.dispose();
    }
  });

  // `CanvasPainter.prepare` decodes images into `_decoded` one primitive at a
  // time, so a throw partway through leaves the already-decoded handles alive.
  // The thumbnail rail documents that path as reachable AND swallows it
  // (page_thumbnail_rail.dart), so without this the leak accumulates silently
  // per failed tile — the very leak this seam exists to close.
  test('releases the painter even when painting throws', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final _ThrowingPainter spy = _ThrowingPainter();

    await expectLater(
      recordPageFrame(
        await imageFrame(),
        reg,
        newPainter: (ui.Canvas canvas, FontRegistry fonts) => spy,
      ),
      throwsA(isA<StateError>()),
    );

    expect(spy.disposed, isTrue,
        reason: 'a backend that throws mid-paint must still be released');
  });

  test('disposes through the abstraction, not the concrete painter', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final _DisposeSpy spy = _DisposeSpy();
    final ui.Picture picture = await recordPageFrame(
      await imageFrame(),
      reg,
      newPainter: (ui.Canvas canvas, FontRegistry fonts) => spy,
    );
    expect(spy.disposed, isTrue);
    expect(spy.painted, isTrue);
    picture.dispose();
  });
}

/// A backend that fails mid-paint, to prove the seam still releases it.
class _ThrowingPainter extends _DisposeSpy {
  @override
  void drawImage(ImagePrimitive p) => throw StateError('corrupt image');
}

/// A real [CanvasPainter] that grabs its decoded-image handles as it is
/// disposed, so the test can assert they were actually released.
class _CapturingPainter extends CanvasPainter {
  _CapturingPainter(super.canvas, super.registry);

  List<ui.Image> captured = <ui.Image>[];

  @override
  void dispose() {
    captured = debugDecodedImages.toList();
    super.dispose();
  }
}

/// A backend that records only whether it was painted and disposed — proving
/// `recordPageFrame` drives the `ReportPainter` contract, not `CanvasPainter`.
class _DisposeSpy implements ReportPainter {
  bool painted = false;
  bool disposed = false;

  @override
  Future<void> prepare(PageFrame frame) async {}
  @override
  void beginPage(PageFormat format) => painted = true;
  @override
  void endPage() {}
  @override
  void pushTransform(JetOffset center, double radians) {}
  @override
  void popTransform() {}
  @override
  void drawRect(RectPrimitive p) {}
  @override
  void drawTextRun(TextRunPrimitive p) {}
  @override
  void drawImage(ImagePrimitive p) {}
  @override
  void drawLine(LinePrimitive p) {}
  @override
  void drawPath(PathPrimitive p) {}
  @override
  void dispose() => disposed = true;
}
