/// Builds the design-time [PageFrame] by reusing the shared render pipeline.
///
/// Constitution IV (NON-NEGOTIABLE): element appearance is produced by the
/// **unchanged** `ElementRenderer.emit` + `CanvasPainter` path — there is no
/// parallel element-drawing code in the designer. The only design-specific part
/// is *where* bands sit (the non-paginated [DesignTimeLayout]); each element is
/// emitted at its page-absolute rect exactly as the render-time layouter does.
library;

import 'dart:ui' as ui;

import '../../domain/page_format.dart';
import '../../domain/report_template.dart';
import '../../rendering/elements/built_in_element_renderers.dart';
import '../../rendering/elements/element_renderer_registry.dart';
import '../../rendering/elements/element_type_registry.dart';
import '../../rendering/elements/render_context.dart';
import '../../rendering/frame/frame_builder.dart';
import '../../rendering/frame/page_frame.dart';
import '../../rendering/paint/canvas_painter.dart';
import '../../rendering/paint/report_painter.dart';
import '../../rendering/text/font_registry.dart';
import '../../rendering/text/metrics_text_measurer.dart';
import 'design_time_layout.dart';

/// Reusable builder that turns a `(template, layout)` pair into a [PageFrame]
/// using the shared renderers, and records that frame into a cacheable
/// `ui.Picture`.
class DesignTimeFrameBuilder {
  /// Creates a builder; renderers and fonts default to the library built-ins.
  DesignTimeFrameBuilder({
    ElementRendererRegistry? renderers,
    FontRegistry? fonts,
  })  : _renderers = renderers ?? _defaultRenderers(),
        fonts = fonts ?? (FontRegistry()..registerDefault()) {
    _ctx = RenderContext(measurer: MetricsTextMeasurer(this.fonts));
  }

  final ElementRendererRegistry _renderers;

  /// The font registry shared between measurement (here) and painting (the
  /// [CanvasPainter] in [recordFrame]) so a glyph is measured and drawn with the
  /// identical font variant.
  final FontRegistry fonts;

  late final RenderContext _ctx;

  static ElementRendererRegistry _defaultRenderers() {
    final ElementTypeRegistry registry = ElementTypeRegistry();
    registerBuiltInElementTypes(registry);
    return registry.renderers;
  }

  /// Emits every element's primitives at its page-absolute rect from [layout].
  PageFrame build(ReportTemplate template, DesignTimeLayout layout) {
    final PageFormat page = PageFormat(
      width: layout.size.width,
      height: layout.size.height,
      margins: template.page.margins,
    );
    final FrameBuilder out = FrameBuilder(page);
    for (final band in template.bands) {
      for (final element in band.elements) {
        final rect = layout.elementRect(element.id);
        if (rect == null) continue;
        _renderers.rendererFor(element).emit(element, _ctx, rect, out);
      }
    }
    return out.build();
  }

  /// Records [frame] into a cacheable [ui.Picture] at 1:1 logical scale. The
  /// caller blits the picture under its view transform (see `FrameCustomPainter`).
  /// Async because [CanvasPainter.prepare] loads fonts and decodes images.
  Future<ui.Picture> recordFrame(PageFrame frame) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), fonts);
    await paintFrame(frame, painter);
    return recorder.endRecording();
  }
}
