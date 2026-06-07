/// Renders a [BarcodeElement] (spec 007a) as a labeled placeholder. Real
/// symbology (Code128/EAN/QR/DataMatrix) is deferred to a dedicated later spec.
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/geometry.dart';
import '../../frame/frame_builder.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// The built-in renderer for `barcode` elements (placeholder).
class BarcodeElementRenderer extends ElementRenderer<BarcodeElement> {
  /// Const constructor.
  const BarcodeElementRenderer();

  @override
  JetSize measure(BarcodeElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(BarcodeElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    emitPlaceholder(out, bounds, el.symbology.name, ctx, elementId: el.id);
  }
}
