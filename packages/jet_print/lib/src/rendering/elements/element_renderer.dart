/// The rendering-side element extension point (spec 007a): measures an element
/// and emits frame primitives for it. Paired with the domain-side `ElementCodec`
/// through `ElementTypeRegistry.register`.
library;

import '../../domain/geometry.dart';
import '../../domain/report_element.dart';
import '../frame/frame_builder.dart';
import 'render_context.dart';

/// Measures and emits primitives for one element type [E].
///
/// `measure`/`emit` take a `covariant ReportElement` (not `E`) for the same
/// reason `ElementCodec` does: it keeps `ElementRenderer<E>` a subtype of
/// `ElementRenderer<ReportElement>` so the registry can hold it. The registry
/// only dispatches after matching the element's `typeKey`, so the implicit
/// narrowing in each concrete renderer is always sound.
abstract class ElementRenderer<E extends ReportElement> {
  /// Const base constructor.
  const ElementRenderer();

  /// The element's natural desired size (no side effects).
  ///
  /// [constraints] is part of the layout contract that 008 will use for
  /// growth/overflow; the 007a built-in renderers return their natural size and
  /// do not yet clamp to it (spec section 7.1 — constraints are reserved for 008).
  JetSize measure(covariant ReportElement element, RenderContext ctx,
      JetConstraints constraints);

  /// Appends this element's primitives to [out], positioned within [bounds].
  void emit(covariant ReportElement element, RenderContext ctx, JetRect bounds,
      FrameBuilder out);
}
