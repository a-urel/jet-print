// lib/src/rendering/paint/canvas_painter.dart
/// The on-screen paint backend (spec 006): the ONLY rendering file that imports
/// Flutter / `dart:ui`. Draws the same line-level runs the measurer produced,
/// using the SAME font variant the measurer measured.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting; // TEMP PROBE import

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
  final Map<ImagePrimitive, ui.Image> _decoded = <ImagePrimitive, ui.Image>{};

  /// Engine font registration is process-global: a typeface loaded under a
  /// `uiFamily` name stays registered for the isolate's lifetime. Re-registering
  /// it (CanvasKit appends without dedupe) bloats the font collection and slows
  /// every later text raster, so the "already registered" guard is shared across
  /// all painters, not per-instance.
  static final Set<String> _engineRegisteredFamilies = <String>{};

  /// Test seam: clears the shared registry so the next painter re-registers.
  @visibleForTesting
  static void debugResetEngineFonts() => _engineRegisteredFamilies.clear();

  final Set<String> _registered;

  @override
  Future<void> prepare(PageFrame frame) async {
    for (final FramePrimitive p in frame.primitives) {
      if (p is TextRunPrimitive) {
        await _ensureFont(p.fontFamily, p.style.weight, p.style.italic);
      } else if (p is ImagePrimitive) {
        final ui.Codec codec = await ui.instantiateImageCodec(p.bytes);
        _decoded[p] = (await codec.getNextFrame()).image;
      }
    }
  }

  /// TEMP PROBE — remove after diagnosing switch leak. Cumulative engine font
  /// registrations; if this climbs unboundedly while bouncing tabs, every record
  /// re-registers fonts and bloats CanvasKit's font collection.
  static int debugFontLoadCount = 0;

  Future<void> _ensureFont(
      String family, JetFontWeight weight, bool italic) async {
    final String uiFamily = uiFontFamily(family, weight, italic);
    if (_registered.contains(uiFamily)) return;
    final Uint8List bytes =
        _registry.bytesFor(family, weight: weight, italic: italic);
    await _loadFont(bytes, fontFamily: uiFamily);
    _registered.add(uiFamily);
    debugPrint('loadFontFromList total=${++debugFontLoadCount} ($uiFamily)');
  }

  @override
  void beginPage(PageFormat format) {}

  @override
  void endPage() {}

  @override
  void drawTextRun(TextRunPrimitive p) {
    final String uiFamily =
        uiFontFamily(p.fontFamily, p.style.weight, p.style.italic);
    final ui.Color color = ui.Color(p.style.color.argb);
    for (final line in p.lines) {
      if (line.text.isEmpty) continue;
      final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        fontFamily: uiFamily,
        fontSize: p.style.fontSize,
      ))
        ..pushStyle(ui.TextStyle(
            color: color, fontFamily: uiFamily, fontSize: p.style.fontSize))
        ..addText(line.text);
      final ui.Paragraph para = pb.build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      final double extra = p.bounds.width - line.width;
      final double dx = switch (p.style.align) {
        JetTextAlign.center => p.bounds.x + extra / 2,
        JetTextAlign.right => p.bounds.x + extra,
        JetTextAlign.left || JetTextAlign.justify => p.bounds.x,
      };
      _canvas.drawParagraph(para, ui.Offset(dx, p.bounds.y + line.top));
      if (p.style.underline) {
        // An explicit stroked segment from the shared geometry helper — NOT
        // ui.TextDecoration, whose placement the PDF backend cannot replicate
        // (021 / research §2, Constitution IV).
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
    final ui.Image? img = _decoded[p];
    if (img == null) return;
    final ImageFit fit = computeImageFit(
        p.fit, p.bounds, img.width.toDouble(), img.height.toDouble());
    _canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(fit.src.x, fit.src.y, fit.src.width, fit.src.height),
      ui.Rect.fromLTWH(fit.dst.x, fit.dst.y, fit.dst.width, fit.dst.height),
      ui.Paint(),
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

  /// Releases every decoded image's GPU texture. Call **after** the frame is
  /// recorded — the recorded `Picture` keeps its own reference, so the handles
  /// are then redundant. On CanvasKit, skipping this leaks a texture per record.
  void dispose() {
    for (final ui.Image image in _decoded.values) {
      image.dispose();
    }
    _decoded.clear();
  }
}
