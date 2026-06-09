/// Renders any element whose type-key is not registered (spec 007a): a visible
/// placeholder labeled with the preserved type-key. The registry returns this
/// for every unregistered type, including a round-tripped `UnknownElement`.
library;

import '../../../domain/geometry.dart';
import '../../../domain/report_element.dart';
import '../../frame/frame_builder.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// The built-in fallback renderer for unregistered element types.
class UnknownElementRenderer extends ElementRenderer<ReportElement> {
  /// Const constructor.
  const UnknownElementRenderer();

  @override
  JetSize measure(
          ReportElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(
      ReportElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    emitPlaceholder(out, bounds, 'Unknown: ${el.typeKey}', ctx,
        elementId: el.id);
  }
}
