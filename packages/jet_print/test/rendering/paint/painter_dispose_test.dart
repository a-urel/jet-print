// Decoded-image lifetime in the `dart:ui` paint backend.
//
// `CanvasPainter.prepare` decodes every `ImagePrimitive` into a `ui.Image`; on
// CanvasKit each one is a GPU texture. `recordPageFrame` is what releases the
// painter, and these tests cover what that seam cannot see: how many textures
// `prepare` decides to decode in the first place, that disposal is safe to
// repeat and safe after a part-way failure, and that the rasterizer releases
// the picture it owns.
//
// The counters they assert on are the only way to observe any of this: every
// consumer builds its painter inside the seam and never hands it back.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jet_print/src/domain/elements/image_source.dart' show JetBoxFit;
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/export/pdf_painter.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/page_rasterizer.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;

const PageFormat _page =
    PageFormat(width: 20, height: 20, margins: JetEdgeInsets.all(0));

/// A genuinely valid PNG (pure-Dart encode, so it works on web too).
Uint8List _validPng() {
  final img.Image image = img.Image(width: 4, height: 2);
  for (int y = 0; y < 2; y++) {
    for (int x = 0; x < 4; x++) {
      image.setPixelRgba(x, y, 32 + 48 * x, 64 + 64 * y, 200, 255);
    }
  }
  return img.encodePng(image);
}

/// Bytes no image codec can decode — `prepare` throws on reaching them.
Uint8List _corruptPng() => Uint8List.fromList(<int>[1, 2, 3, 4]);

PageFrame _frameWithImages(List<Uint8List> images) {
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

FontRegistry _fonts() => FontRegistry()..registerDefault();

/// Wraps a real [ui.Codec] and records whether it was disposed.
///
/// `ui.Codec` is a plain abstract class, so a test can implement it. This
/// observes the REAL handle rather than a counter: a counter cannot tell
/// "disposed" from "decremented", so a test asserting one would still pass if
/// the `dispose()` call were deleted and the bookkeeping left behind.
class _SpyCodec implements ui.Codec {
  _SpyCodec(this._inner);

  final ui.Codec _inner;
  bool disposed = false;

  @override
  int get frameCount => _inner.frameCount;

  @override
  int get repetitionCount => _inner.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() => _inner.getNextFrame();

  @override
  void dispose() {
    disposed = true;
    _inner.dispose();
  }
}

/// A text run of [lineCount] laid-out lines. Lines are built directly rather
/// than measured: the painter never re-wraps them, so the geometry only has to
/// be self-consistent.
TextRunPrimitive _text({int lineCount = 1, String text = 'Hg'}) =>
    TextRunPrimitive(
      bounds: const JetRect(x: 0, y: 0, width: 20, height: 20),
      lines: <TextLine>[
        for (int i = 0; i < lineCount; i++)
          TextLine(
            text: text,
            width: 12,
            top: i * 6.0,
            baseline: i * 6.0 + 5,
            height: 6,
          ),
      ],
      style: const JetTextStyle(fontSize: 5),
      fontFamily: FontRegistry.defaultFamily,
    );

PageFrame _frameWith(List<FramePrimitive> primitives) {
  final FrameBuilder b = FrameBuilder(_page);
  for (final FramePrimitive p in primitives) {
    b.add(p);
  }
  return b.build();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CanvasPainter.debugResetDecodedImageCounters();
    // Cleared too, or `isNotNull` below stops meaning "this call assigned it":
    // the static survives the test that set it, so a later test could read a
    // disposed picture left over from an earlier one and pass on stale state.
    PageRasterizer.debugLastPicture = null;
  });

  test('dispose is reachable through a ReportPainter reference', () async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    // The defect: the three missed call sites declare exactly this type, so
    // `dispose` had to exist on the INTERFACE to be callable at all.
    final ReportPainter painter = CanvasPainter(ui.Canvas(rec), _fonts());

    await paintFrame(_frameWithImages(<Uint8List>[_validPng()]), painter);
    rec.endRecording();
    expect(CanvasPainter.debugLiveDecodedImages, 1,
        reason: 'prepare decoded one image');

    painter.dispose();

    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });

  test('PdfPainter.dispose is a no-op: it owns no native handles', () {
    final ReportPainter pdf = PdfPainter(_fonts());
    // This backend decodes to plain Dart pixel buffers and hands its fonts and
    // images to the PDF document, so it has nothing to release — but it still
    // DECLARES an empty `dispose`, because `ReportPainter.dispose` is abstract
    // and `implements` forces every backend to answer the question.
    expect(pdf.dispose, returnsNormally);
  });

  test('dispose is idempotent', () async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), _fonts());
    await paintFrame(_frameWithImages(<Uint8List>[_validPng()]), painter);
    rec.endRecording();

    painter.dispose();
    // A second call must not re-dispose an already-disposed ui.Image (which
    // asserts in debug) — the call sites use try/finally, so double-dispose is
    // reachable whenever a caller disposes explicitly and then unwinds.
    expect(painter.dispose, returnsNormally);
    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });

  test('dispose releases images decoded before prepare threw', () async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), _fonts());
    final PageFrame frame =
        _frameWithImages(<Uint8List>[_validPng(), _corruptPng()]);

    await expectLater(paintFrame(frame, painter), throwsA(anything));
    expect(CanvasPainter.debugLiveDecodedImages, 1,
        reason: 'the first image decoded before the second one threw');

    painter.dispose();

    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });

  test('one image on many rows is decoded once, not once per row', () async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), _fonts());
    // A single ImageElement on N detail rows emits N primitives that share ONE
    // Uint8List instance (the renderer passes `source.bytes` straight through)
    // at N different bounds. The decoded texture depends only on those bytes —
    // fit and opacity are applied at draw time — so this must cost one decode,
    // not one per row.
    final Uint8List shared = _validPng();
    final PageFrame frame = _frameWith(<FramePrimitive>[
      for (int row = 0; row < 4; row++)
        ImagePrimitive(
          bounds: JetRect(x: 0, y: row * 4.0, width: 4, height: 4),
          bytes: shared,
          fit: JetBoxFit.contain,
        ),
    ]);

    await paintFrame(frame, painter);
    rec.endRecording();
    expect(CanvasPainter.debugTotalDecodedImages, 1,
        reason: 'four rows, one image, one decode');
    expect(CanvasPainter.debugLiveDecodedImages, 1);

    painter.dispose();

    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });

  test('every image codec is released once its frame is decoded', () async {
    // The codec is a native decoder in its own right: disposing the `ui.Image`
    // it yields does not release it, and nothing else did. It has no
    // `debugDisposed`, so the painter takes an injectable instantiator and the
    // test hands back a spy over the real codec.
    final List<_SpyCodec> spies = <_SpyCodec>[];
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(
      ui.Canvas(rec),
      _fonts(),
      codecInstantiator: (Uint8List bytes) async {
        final _SpyCodec spy = _SpyCodec(await ui.instantiateImageCodec(bytes));
        spies.add(spy);
        return spy;
      },
    );
    final PageFrame frame = _frameWith(<FramePrimitive>[
      ImagePrimitive(
        bounds: const JetRect(x: 0, y: 0, width: 4, height: 4),
        bytes: _validPng(),
        fit: JetBoxFit.contain,
      ),
      ImagePrimitive(
        bounds: const JetRect(x: 0, y: 8, width: 4, height: 4),
        bytes: _validPng(),
        fit: JetBoxFit.contain,
      ),
    ]);

    await paintFrame(frame, painter);
    rec.endRecording();

    expect(spies, hasLength(2),
        reason: 'two distinct buffers, so two codecs were created');
    expect(spies.every((_SpyCodec c) => c.disposed), isTrue);

    painter.dispose();
  });

  test('PageRasterizer disposes the picture it recorded', () async {
    // The recorded `ui.Picture` is a third native handle, independent of both
    // the painter's source textures and `toImage`'s result — and it holds refs
    // to those source textures, so dropping it leaves GC finalization as the
    // only thing bounding either. Every PNG export records one.
    await const PageRasterizer()
        .rasterize(_frameWith(<FramePrimitive>[_text()]), _fonts());

    expect(PageRasterizer.debugLastPicture, isNotNull);
    expect(PageRasterizer.debugLastPicture!.debugDisposed, isTrue);
  });

  test('PageRasterizer leaves no decoded texture alive', () async {
    await const PageRasterizer()
        .rasterize(_frameWithImages(<Uint8List>[_validPng()]), _fonts());

    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });

  test('PageRasterizer releases decoded textures when painting throws',
      () async {
    final PageFrame frame =
        _frameWithImages(<Uint8List>[_validPng(), _corruptPng()]);

    await expectLater(
        const PageRasterizer().rasterize(frame, _fonts()), throwsA(anything));

    expect(CanvasPainter.debugTotalDecodedImages, greaterThan(0),
        reason: 'a texture must have been decoded before the throw');
    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });
}
