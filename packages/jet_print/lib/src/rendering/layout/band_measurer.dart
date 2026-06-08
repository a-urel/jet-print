/// Measures a body band to its grown height with each element's grown, band-local
/// box (spec 008a §5). Pure and position-independent, so the layouter measures
/// each element only once and reuses the result for both the page-break decision
/// and placement (the renderer's `emit` re-derives its own line content — the
/// 007a seam — which this pass does not change).
///
/// **Grow-only, height-only:** an element keeps its authored width (the renderer
/// wraps at the element's own width and grows vertically) and never shrinks below
/// its authored height — it only stretches when its measured content needs more
/// room. A growing element does NOT push its siblings down (banded +
/// absolute-in-band; no reflow): the band height is the maximum element bottom,
/// floored at the designed height.
library;

import '../../domain/geometry.dart';
import '../../domain/report_element.dart';
import '../elements/element_renderer_registry.dart';
import '../elements/render_context.dart';
import '../fill/filled_report.dart';

/// A band measured to its grown [height], with each element paired with its
/// grown band-local [bounds] (reused for placement, so the layouter measures an
/// element's geometry only once — the renderer's `emit` re-derives its own line
/// content separately, the unchanged 007a seam).
class MeasuredBand {
  /// Creates a measured band.
  const MeasuredBand(this.height, this.elements);

  /// The grown band height (>= the band's designed height), in points.
  final double height;

  /// Each element with its grown, band-local box (reused for placement, so the
  /// layouter does not re-measure an element's geometry at emit time).
  final List<({ReportElement element, JetRect bounds})> elements;
}

/// Measures [FilledBand]s for layout, delegating per-element sizing to the
/// registered [ElementRenderer]s.
class BandMeasurer {
  /// Creates a measurer over the renderer [_registry] and render [_ctx].
  BandMeasurer(this._registry, this._ctx);

  final ElementRendererRegistry _registry;
  final RenderContext _ctx;

  /// Measures [band] into its grown height and per-element grown boxes.
  MeasuredBand measure(FilledBand band) {
    final List<({ReportElement element, JetRect bounds})> boxes =
        <({ReportElement element, JetRect bounds})>[];
    double maxBottom = band.height;
    for (final ReportElement el in band.elements) {
      final JetSize natural = _registry.rendererFor(el).measure(
            el,
            _ctx,
            JetConstraints(maxWidth: el.bounds.width),
          );
      final double grownHeight = natural.height > el.bounds.height
          ? natural.height
          : el.bounds.height;
      boxes.add((
        element: el,
        bounds: JetRect(
          x: el.bounds.x,
          y: el.bounds.y,
          width: el.bounds.width,
          height: grownHeight,
        ),
      ));
      final double bottom = el.bounds.y + grownHeight;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    return MeasuredBand(maxBottom, boxes);
  }
}
