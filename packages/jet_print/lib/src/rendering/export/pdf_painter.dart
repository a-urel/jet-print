// lib/src/rendering/export/pdf_painter.dart
/// The PDF paint backend (spec 012): a pure-Dart [ReportPainter] over
/// `package:pdf`'s low-level `PdfDocument`/`PdfPage`/`PdfGraphics` API.
///
/// Draws the SAME pre-measured frame primitives the preview paints — text at
/// exact baselines from the same measurer, fonts embedded from the same
/// [FontRegistry] bytes, images placed via the shared [computeImageFit] —
/// so WYSIWYG holds by construction (Constitution IV, FR-001/003).
///
/// Deterministic by construction (FR-007): the document ID is fixed (the only
/// always-written nondeterministic output of dart_pdf), no `/Info` dictionary
/// is ever constructed (its `/CreationDate` would read the wall clock), and
/// `verbose` stays false. No clock, randomness, or ambient-locale read exists
/// anywhere in this file.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';

import '../../domain/page_format.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../frame/page_frame.dart';
import '../frame/primitive.dart';
import '../paint/image_fit.dart';
import '../paint/report_painter.dart';
import '../text/font_registry.dart';
import '../text/underline_metrics.dart';

/// Paints [PageFrame]s into one PDF document; call [save] after the last page.
///
/// One instance per export: pages accumulate in paint order, fonts embed once
/// per distinct registry byte source, images embed once per distinct byte
/// buffer. The top-left frame coordinates are mapped to PDF's bottom-left
/// origin PER DRAW CALL (`y' = pageHeight - y`) — never via a global negative
/// CTM, which would mirror glyph outlines (research §6).
class PdfPainter implements ReportPainter {
  /// Creates a painter resolving font bytes via [fonts].
  PdfPainter(FontRegistry fonts)
      : _fonts = fonts,
        _document = _FixedIdPdfDocument();

  final FontRegistry _fonts;
  final PdfDocument _document;

  /// TTF programs already embedded, keyed by the registry's byte instance —
  /// [FontRegistry.bytesFor] returns the same instance for every variant that
  /// resolves to the same entry, so fallback variants share one embed.
  final Map<Uint8List, PdfTtfFont> _embeddedFonts = <Uint8List, PdfTtfFont>{};

  /// Images already embedded, keyed by the primitive's byte instance.
  final Map<Uint8List, PdfImage> _embeddedImages = <Uint8List, PdfImage>{};

  /// Pixels decoded in [prepare], keyed by primitive (value equality).
  final Map<ImagePrimitive, _DecodedImage> _decoded =
      <ImagePrimitive, _DecodedImage>{};

  PdfGraphics? _graphics;
  double _pageHeight = 0;

  /// The current page's graphics (only valid between begin/endPage).
  PdfGraphics get _g {
    final PdfGraphics? g = _graphics;
    if (g == null) {
      throw StateError('draw call outside beginPage/endPage');
    }
    return g;
  }

  /// Maps a top-left-origin y to PDF's bottom-left origin.
  double _mapY(double y) => _pageHeight - y;

  @override
  Future<void> prepare(PageFrame frame) async {
    for (final FramePrimitive p in frame.primitives) {
      if (p is ImagePrimitive && !_decoded.containsKey(p)) {
        final _DecodedImage? decoded = _DecodedImage.decode(p.bytes);
        if (decoded != null) _decoded[p] = decoded;
      }
    }
  }

  @override
  void beginPage(PageFormat format) {
    final PdfPage page = PdfPage(
      _document,
      pageFormat: PdfPageFormat(format.width, format.height),
    );
    _graphics = page.getGraphics();
    _pageHeight = format.height;
  }

  @override
  void endPage() {
    _graphics = null;
  }

  @override
  void drawTextRun(TextRunPrimitive p) {
    final PdfGraphics g = _g;
    final Uint8List bytes = _fonts.bytesFor(
      p.fontFamily,
      weight: p.style.weight,
      italic: p.style.italic,
    );
    final PdfTtfFont font = _embeddedFonts.putIfAbsent(
      bytes,
      () => PdfTtfFont(
        _document,
        bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    _withAlpha(g, p.style.color, () {
      g.setFillColor(_pdfColor(p.style.color));
      for (final line in p.lines) {
        if (line.text.isEmpty) continue;
        // CanvasPainter's alignment math: distribute the unused width.
        final double extra = p.bounds.width - line.width;
        final double dx = switch (p.style.align) {
          JetTextAlign.center => p.bounds.x + extra / 2,
          JetTextAlign.right => p.bounds.x + extra,
          JetTextAlign.left || JetTextAlign.justify => p.bounds.x,
        };
        // line.baseline is measured from the BLOCK top (= top + ascent), so
        // the page-space baseline is bounds.y + line.baseline — the same
        // glyph baseline the canvas backend produces. Never re-wrap.
        g.drawString(
          font,
          p.style.fontSize,
          line.text,
          dx,
          _mapY(p.bounds.y + line.baseline),
        );
        if (p.style.underline) {
          // The same explicit segment CanvasPainter strokes, from the same
          // shared geometry helper (021 / research §2, Constitution IV).
          final ({double offset, double thickness}) u =
              underlineFor(p.style.fontSize);
          final double y = _mapY(p.bounds.y + line.baseline + u.offset);
          g.setStrokeColor(_pdfColor(p.style.color));
          g.setLineWidth(u.thickness);
          g.drawLine(dx, y, dx + line.width, y);
          g.strokePath();
        }
      }
    });
  }

  @override
  void drawImage(ImagePrimitive p) {
    final _DecodedImage? decoded = _decoded[p];
    if (decoded == null) return; // undecodable bytes: draw nothing, like
    // an unresolved source upstream — never crash the export (B5).
    final PdfGraphics g = _g;
    final PdfImage image = _embeddedImages.putIfAbsent(
      p.bytes,
      () => decoded.embed(_document),
    );
    final ImageFit fit = computeImageFit(
      p.fit,
      p.bounds,
      decoded.width.toDouble(),
      decoded.height.toDouble(),
    );
    // drawImageRect semantics: clip to dst, then draw the FULL image scaled
    // so the src window lands exactly on dst.
    final double scaleX = fit.dst.width / fit.src.width;
    final double scaleY = fit.dst.height / fit.src.height;
    final double fullWidth = decoded.width * scaleX;
    final double fullHeight = decoded.height * scaleY;
    final double fullLeft = fit.dst.x - fit.src.x * scaleX;
    final double fullTop = fit.dst.y - fit.src.y * scaleY;
    g.saveContext();
    g.drawRect(
      fit.dst.x,
      _mapY(fit.dst.y + fit.dst.height),
      fit.dst.width,
      fit.dst.height,
    );
    g.clipPath();
    g.drawImage(
      image,
      fullLeft,
      _mapY(fullTop + fullHeight),
      fullWidth,
      fullHeight,
    );
    g.restoreContext();
  }

  @override
  void drawLine(LinePrimitive p) {
    final PdfGraphics g = _g;
    _withAlpha(g, p.color, () {
      g.setStrokeColor(_pdfColor(p.color));
      g.setLineWidth(p.strokeWidth);
      g.drawLine(
        p.start.dx,
        _mapY(p.start.dy),
        p.end.dx,
        _mapY(p.end.dy),
      );
      g.strokePath();
    });
  }

  @override
  void drawRect(RectPrimitive p) {
    final PdfGraphics g = _g;
    final double left = p.bounds.x;
    final double bottom = _mapY(p.bounds.y + p.bounds.height);
    // Fill first, then stroke on top — CanvasPainter's order.
    final JetColor? fill = p.fill;
    if (fill != null) {
      _withAlpha(g, fill, () {
        g.setFillColor(_pdfColor(fill));
        g.drawRect(left, bottom, p.bounds.width, p.bounds.height);
        g.fillPath();
      });
    }
    final JetColor? stroke = p.stroke;
    if (stroke != null) {
      _withAlpha(g, stroke, () {
        g.setStrokeColor(_pdfColor(stroke));
        g.setLineWidth(p.strokeWidth);
        g.drawRect(left, bottom, p.bounds.width, p.bounds.height);
        g.strokePath();
      });
    }
  }

  @override
  void drawPath(PathPrimitive p) {
    final PdfGraphics g = _g;
    void replay() {
      for (final PathCommand c in p.commands) {
        switch (c) {
          case MoveTo():
            g.moveTo(c.to.dx, _mapY(c.to.dy));
          case LineTo():
            g.lineTo(c.to.dx, _mapY(c.to.dy));
          case ClosePath():
            g.closePath();
        }
      }
    }

    // A PDF paint operator consumes the current path, so the path is replayed
    // per pass — keeping CanvasPainter's fill-first-then-stroke order.
    final JetColor? fill = p.fill;
    if (fill != null) {
      _withAlpha(g, fill, () {
        g.setFillColor(_pdfColor(fill));
        replay();
        g.fillPath();
      });
    }
    final JetColor? stroke = p.stroke;
    if (stroke != null) {
      _withAlpha(g, stroke, () {
        g.setStrokeColor(_pdfColor(stroke));
        g.setLineWidth(p.strokeWidth);
        replay();
        g.strokePath();
      });
    }
  }

  /// Serializes the accumulated document. Call once, after the last page.
  Future<Uint8List> save() => _document.save();

  static PdfColor _pdfColor(JetColor color) => PdfColor.fromInt(color.argb);

  /// Runs [draw] with the color's alpha installed as an ExtGState when it is
  /// not fully opaque (PDF color operators carry no alpha). The state is
  /// scoped with save/restore so it cannot leak into later primitives —
  /// matching CanvasPainter's per-Paint alpha.
  static void _withAlpha(PdfGraphics g, JetColor color, void Function() draw) {
    final int alpha = (color.argb >> 24) & 0xff;
    if (alpha == 0xff) {
      draw();
      return;
    }
    g.saveContext();
    g.setGraphicState(PdfGraphicState(opacity: alpha / 0xff));
    draw();
    g.restoreContext();
  }
}

/// Pixels decoded once in [PdfPainter.prepare], embeddable on first draw.
class _DecodedImage {
  _DecodedImage._(this.width, this.height, this._embed);

  /// Source width, in pixels.
  final int width;

  /// Source height, in pixels.
  final int height;

  final PdfImage Function(PdfDocument document) _embed;

  /// Embeds the image into [document] (JPEG passthrough; everything else as
  /// raw RGBA with the alpha channel as an `/SMask`).
  PdfImage embed(PdfDocument document) => _embed(document);

  /// Decodes [bytes]; returns null when undecodable (drawn as nothing).
  static _DecodedImage? decode(Uint8List bytes) {
    // JPEG passthrough: no re-encode, no lossy-on-lossy (research §5).
    if (bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      final img.Image? info = img.decodeJpg(bytes);
      if (info == null) return null;
      return _DecodedImage._(
        info.width,
        info.height,
        (PdfDocument document) => PdfImage.jpeg(document, image: bytes),
      );
    }
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final img.Image rgba = decoded.convert(numChannels: 4);
    final Uint8List pixels = rgba.getBytes(order: img.ChannelOrder.rgba);
    return _DecodedImage._(
      decoded.width,
      decoded.height,
      (PdfDocument document) => PdfImage(
        document,
        image: pixels,
        width: decoded.width,
        height: decoded.height,
      ),
    );
  }
}

/// A [PdfDocument] whose `/ID` is a constant: the ID is otherwise derived
/// from the wall clock + a secure random source, is ALWAYS written, and has
/// no constructor parameter — the virtual getter is the sanctioned override
/// point (research §2). Everything else inherits dart_pdf defaults
/// (`verbose: false`, deflate compression).
class _FixedIdPdfDocument extends PdfDocument {
  _FixedIdPdfDocument();

  static final Uint8List _fixedId = Uint8List(32);

  @override
  Uint8List get documentID => _fixedId;
}
