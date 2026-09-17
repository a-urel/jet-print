// lib/src/rendering/paint/canvas_painter.dart
/// The on-screen paint backend. Draws the same line-level runs the measurer
/// produced, using the SAME font variant the measurer measured.
///
/// One of three rendering files allowed to import Flutter / `dart:ui` —
/// with `page_rasterizer.dart` (PNG encoding) and `record_page_frame.dart`
/// (the recorder/painter/dispose seam). `layer_boundaries_test.dart` pins that
/// allowlist. Consumers do not build this painter directly; they go through
/// `recordPageFrame`, which is what releases it.
library;

import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../domain/geometry.dart';
import '../../domain/page_format.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../frame/page_frame.dart';
import '../frame/primitive.dart';
import '../text/font_registry.dart';
import '../text/ui_font_family.dart';
import '../text/underline_metrics.dart';
import 'image_fit.dart';
import 'report_painter.dart';

/// Loads font [bytes] into the engine under [fontFamily]. Defaults to
/// `dart:ui`'s `loadFontFromList`; injectable for tests.
typedef FontLoader = Future<void> Function(Uint8List bytes,
    {String? fontFamily});

/// Paints a [PageFrame] onto a `dart:ui` [ui.Canvas].
class CanvasPainter implements ReportPainter {
  /// Creates a painter drawing to [_canvas], resolving fonts via [_registry].
  /// [fontLoader] overrides the engine font loader (tests). [registeredFamilies]
  /// overrides the process-global registry of already-registered engine font
  /// families (tests pass a fresh set for isolation).
  CanvasPainter(
    this._canvas,
    this._registry, {
    FontLoader? fontLoader,
    Set<String>? registeredFamilies,
  })  : _loadFont = fontLoader ?? ui.loadFontFromList,
        _registered = registeredFamilies ?? _engineRegisteredFamilies;

  final ui.Canvas _canvas;
  final FontRegistry _registry;
  final FontLoader _loadFont;

  /// Decoded textures, keyed by the IDENTITY of the encoded byte buffer.
  ///
  /// Not by the primitive: a decoded image depends only on its bytes — `fit`,
  /// `opacity` and `bounds` are applied at draw time — while a primitive's
  /// value equality includes all of those. Keying on the primitive therefore
  /// decoded one texture PER ROW for a single image repeated down a band, and
  /// made every cache probe an O(bytes) structural hash. The renderer passes
  /// `BytesImageSource.bytes` straight through, so every row of one element
  /// shares one buffer instance and identity is the right test.
  final Map<Uint8List, ui.Image> _decoded = HashMap<Uint8List, ui.Image>(
    equals: identical,
    hashCode: identityHashCode,
  );

  /// Every `ui.Paragraph` built by [drawTextRun] this record — each already
  /// released. Kept only so tests can assert the release actually happened, so
  /// it is populated under `assert` and stays EMPTY in release builds: one
  /// entry per laid-out line per record is real per-line allocation, and no
  /// shipped code reads it.
  ///
  /// One paragraph is built per laid-out LINE, so a text-heavy page produces
  /// many; none was ever disposed, which leaked a paragraph per line per
  /// record. Unlike [_decoded] these are released the moment the draw returns
  /// rather than at [dispose]: `Canvas.drawParagraph` has the paragraph paint
  /// ITSELF into the canvas (`_NativeParagraph._paint`), so the recording holds
  /// its own reference by the time the draw returns and the handle is redundant
  /// from that point. Releasing too early is not a silent corruption either —
  /// `drawParagraph` asserts `!debugDisposed`. That keeps the peak at one live
  /// paragraph instead of one per line of the page.
  final List<ui.Paragraph> _paragraphs = <ui.Paragraph>[];

  /// Engine font registration is process-global: a typeface loaded under a
  /// `uiFamily` name stays registered for the isolate's lifetime. Re-registering
  /// it (CanvasKit appends without dedupe) bloats the font collection and slows
  /// every later text raster, so the "already registered" guard is shared across
  /// all painters, not per-instance.
  static final Set<String> _engineRegisteredFamilies = <String>{};

  /// Test seam: clears the shared registry so the next painter re-registers.
  @visibleForTesting
  static void debugResetEngineFonts() => _engineRegisteredFamilies.clear();

  /// Test seam: images [prepare] has decoded and [dispose] has not yet
  /// released, summed across every painter in the isolate. It is the only way
  /// to observe a leak at a call site that builds its painter internally and
  /// never hands it back (the rasterizer, the preview, the thumbnail rail), so
  /// a non-zero value once a frame has been recorded IS the leak.
  @visibleForTesting
  static int debugLiveDecodedImages = 0;

  /// Test seam: how many images [prepare] has decoded in this isolate, ever.
  ///
  /// Monotonic, so — unlike the [debugLiveDecodedImages] gauge — it cannot be
  /// missed by sampling between async turns, which matters when a decode and
  /// its disposal happen in the SAME turn (the path where `prepare` throws).
  /// A leak test pairs the two: this one proves the run actually decoded
  /// something, so a harness that silently decoded nothing fails as vacuous
  /// instead of passing.
  @visibleForTesting
  static int debugTotalDecodedImages = 0;

  /// Test seam: zeroes the decoded-image counters so each test starts clean.
  @visibleForTesting
  static void debugResetDecodedImageCounters() {
    debugLiveDecodedImages = 0;
    debugTotalDecodedImages = 0;
  }

  final Set<String> _registered;

  @override
  Future<void> prepare(PageFrame frame) async {
    for (final FramePrimitive p in frame.primitives) {
      if (p is TextRunPrimitive) {
        await _ensureFont(p.fontFamily, p.style.weight, p.style.italic);
      } else if (p is ImagePrimitive) {
        if (_decoded.containsKey(p.bytes)) continue;
        final ui.Codec codec = await ui.instantiateImageCodec(p.bytes);
        _decoded[p.bytes] = (await codec.getNextFrame()).image;
        assert(() {
          debugLiveDecodedImages++;
          debugTotalDecodedImages++;
          return true;
        }());
      }
    }
  }

  Future<void> _ensureFont(
      String family, JetFontWeight weight, bool italic) async {
    final String uiFamily = uiFontFamily(family, weight, italic);
    if (_registered.contains(uiFamily)) return;
    final Uint8List bytes =
        _registry.bytesFor(family, weight: weight, italic: italic);
    await _loadFont(bytes, fontFamily: uiFamily);
    _registered.add(uiFamily);
  }

  @override
  void beginPage(PageFormat format) {}

  @override
  void endPage() {}

  @override
  void pushTransform(JetOffset center, double radians) {
    _canvas.save();
    _canvas.translate(center.dx, center.dy);
    _canvas.rotate(radians);
    _canvas.translate(-center.dx, -center.dy);
  }

  @override
  void popTransform() => _canvas.restore();

  @override
  void drawTextRun(TextRunPrimitive p) {
    final String uiFamily =
        uiFontFamily(p.fontFamily, p.style.weight, p.style.italic);
    final ui.Color color = ui.Color(p.style.color.argb);
    for (final line in p.lines) {
      if (line.text.isEmpty) continue;
      // Placement is computed before the paragraph exists, so the only
      // statements between `build()` and the `try` are the assignment itself:
      // `layout` runs INSIDE the guard, because a paragraph that throws while
      // laying out is exactly the handle the `finally` exists to release.
      final double extra = p.bounds.width - line.width;
      final double dx = switch (p.style.align) {
        JetTextAlign.center => p.bounds.x + extra / 2,
        JetTextAlign.right => p.bounds.x + extra,
        JetTextAlign.left || JetTextAlign.justify => p.bounds.x,
      };
      final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        fontFamily: uiFamily,
        fontSize: p.style.fontSize,
      ))
        ..pushStyle(ui.TextStyle(
            color: color, fontFamily: uiFamily, fontSize: p.style.fontSize))
        ..addText(line.text);
      final ui.Paragraph para = pb.build();
      try {
        assert(() {
          _paragraphs.add(para);
          return true;
        }());
        para.layout(const ui.ParagraphConstraints(width: double.infinity));
        _canvas.drawParagraph(para, ui.Offset(dx, p.bounds.y + line.top));
      } finally {
        para.dispose();
      }
      if (p.style.underline) {
        // An explicit stroked segment from the shared geometry helper — NOT
        // ui.TextDecoration, whose placement the PDF backend cannot replicate
        // (021).
        final ({double offset, double thickness}) u =
            underlineFor(p.style.fontSize);
        final double y = p.bounds.y + line.baseline + u.offset;
        _canvas.drawLine(
          ui.Offset(dx, y),
          ui.Offset(dx + line.width, y),
          ui.Paint()
            ..color = color
            ..strokeWidth = u.thickness
            ..style = ui.PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  void drawImage(ImagePrimitive p) {
    final ui.Image? img = _decoded[p.bytes];
    if (img == null) return;
    final ImageFit fit = computeImageFit(
        p.fit, p.bounds, img.width.toDouble(), img.height.toDouble());
    _canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(fit.src.x, fit.src.y, fit.src.width, fit.src.height),
      ui.Rect.fromLTWH(fit.dst.x, fit.dst.y, fit.dst.width, fit.dst.height),
      ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, p.opacity),
    );
  }

  @override
  void drawLine(LinePrimitive p) {
    _canvas.drawLine(
      ui.Offset(p.start.dx, p.start.dy),
      ui.Offset(p.end.dx, p.end.dy),
      ui.Paint()
        ..color = ui.Color(p.color.argb)
        ..strokeWidth = p.strokeWidth
        ..style = ui.PaintingStyle.stroke,
    );
  }

  @override
  void drawRect(RectPrimitive p) {
    final ui.Rect r = ui.Rect.fromLTWH(
        p.bounds.x, p.bounds.y, p.bounds.width, p.bounds.height);
    final JetColor? fill = p.fill;
    if (fill != null) {
      _canvas.drawRect(r, ui.Paint()..color = ui.Color(fill.argb));
    }
    final JetColor? stroke = p.stroke;
    if (stroke != null) {
      _canvas.drawRect(
          r,
          ui.Paint()
            ..color = ui.Color(stroke.argb)
            ..strokeWidth = p.strokeWidth
            ..style = ui.PaintingStyle.stroke);
    }
  }

  @override
  void drawPath(PathPrimitive p) {
    final ui.Path path = ui.Path();
    for (final PathCommand c in p.commands) {
      switch (c) {
        case MoveTo():
          path.moveTo(c.to.dx, c.to.dy);
        case LineTo():
          path.lineTo(c.to.dx, c.to.dy);
        case ClosePath():
          path.close();
      }
    }
    final JetColor? fill = p.fill;
    if (fill != null) {
      _canvas.drawPath(path, ui.Paint()..color = ui.Color(fill.argb));
    }
    final JetColor? stroke = p.stroke;
    if (stroke != null) {
      _canvas.drawPath(
          path,
          ui.Paint()
            ..color = ui.Color(stroke.argb)
            ..strokeWidth = p.strokeWidth
            ..style = ui.PaintingStyle.stroke);
    }
  }

  /// The images decoded in [prepare]; exposed for tests to assert disposal.
  @visibleForTesting
  Iterable<ui.Image> get debugDecodedImages => _decoded.values;

  /// The paragraphs built by [drawTextRun]; exposed for tests to assert
  /// disposal.
  @visibleForTesting
  Iterable<ui.Paragraph> get debugParagraphs => _paragraphs;

  /// Releases every decoded image's GPU texture. Call **after** the frame is
  /// recorded — the recorded `Picture` keeps its own reference, so the handles
  /// are then redundant. On CanvasKit, skipping this leaks a texture per record.
  ///
  /// Paragraphs need no release here: [drawTextRun] frees each one as soon as
  /// its draw returns (see [_paragraphs]), so this only resets that gauge.
  @override
  void dispose() {
    for (final ui.Image image in _decoded.values) {
      image.dispose();
    }
    assert(() {
      debugLiveDecodedImages -= _decoded.length;
      return true;
    }());
    // Cleared so a second call is a no-op rather than re-disposing an already
    // disposed handle (which asserts in debug): the call sites release in a
    // `finally`, so an explicit dispose followed by an unwinding one is normal.
    _decoded.clear();
    _paragraphs.clear();
  }
}
