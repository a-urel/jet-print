/// Renders a [BarcodeElement] as real symbology (spec 036): filled module rects
/// plus HRI text, or the shared placeholder when the data cannot be encoded.
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/styles/text_style.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../../text/text_measurer.dart';
import '../barcode/barcode_encoder.dart';
import '../barcode/barcode_symbol.dart';
import '../barcode/package_barcode_encoder.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// The built-in renderer for `barcode` elements.
class BarcodeElementRenderer extends ElementRenderer<BarcodeElement> {
  /// Creates a renderer; [encoder] defaults to the package adapter.
  const BarcodeElementRenderer({this.encoder = const PackageBarcodeEncoder()});

  /// The encoder seam (injectable for tests).
  final BarcodeEncoder encoder;

  @override
  JetSize measure(
          BarcodeElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(
      BarcodeElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    // Value: the resolved literal. An empty bound field previews as QR.
    final bool previewBoundField = el.data.isEmpty && el.dataField != null;
    final String value = previewBoundField ? el.dataField! : el.data;
    final BarcodeSymbology symbology =
        previewBoundField ? BarcodeSymbology.qrCode : el.symbology;

    // Empty data with no bound field → placeholder.
    if (value.isEmpty) {
      emitPlaceholder(out, bounds, el.symbology.name, ctx,
          elementId: el.id, color: el.color);
      return;
    }

    // Quiet-zone inset (FR-007).
    final double margin = el.quietZone
        ? (0.1 * (bounds.width < bounds.height ? bounds.width : bounds.height))
            .clamp(0, 0.25 * bounds.width)
            .toDouble()
        : 0;
    final double cx = bounds.x + margin;
    final double cy = bounds.y + margin;
    final double cw = bounds.width - 2 * margin;
    final double ch = bounds.height - 2 * margin;
    if (cw <= 0 || ch <= 0) {
      emitPlaceholder(out, bounds, el.symbology.name, ctx,
          elementId: el.id, color: el.color);
      return;
    }

    final BarcodeEncodeResult result = encoder.encode(
      symbology,
      value,
      width: cw,
      height: ch,
      showText: el.showText,
      eccLevel: el.eccLevel,
    );

    if (result is! BarcodeEncoded) {
      emitPlaceholder(out, bounds, el.symbology.name, ctx,
          elementId: el.id, color: el.color);
      return;
    }

    final BarcodeSymbol sym = result.symbol;
    // Center the (possibly square) symbol within the content box.
    final double ox = cx + (cw - sym.spaceWidth) / 2;
    final double oy = cy + (ch - sym.spaceHeight) / 2;

    for (final BarcodeModule m in sym.modules) {
      out.add(RectPrimitive(
        bounds: JetRect(
            x: ox + m.left, y: oy + m.top, width: m.width, height: m.height),
        fill: el.color,
        elementId: el.id,
      ));
    }
    for (final BarcodeHriText t in sym.texts) {
      final JetTextStyle style =
          JetTextStyle(fontSize: t.height * 0.9, color: el.color);
      final JetRect tb = JetRect(
          x: ox + t.left, y: oy + t.top, width: t.width, height: t.height);
      final MeasuredText measured =
          ctx.measurer.measure(t.text, style, maxWidth: t.width);
      out.add(TextRunPrimitive(
        bounds: tb,
        lines: measured.lines,
        style: style,
        fontFamily: measured.fontFamily,
        elementId: el.id,
      ));
    }
  }
}
