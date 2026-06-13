import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/shape_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

Future<Uint8List> _solidPng(int w, int h, int argb) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = ui.Color(argb));
  final ui.Image img = await rec.endRecording().toImage(w, h);
  final ByteData data = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paints a fixture frame (text + rect + line + image) to a smoke golden',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final MetricsTextMeasurer measurer = MetricsTextMeasurer(reg);
    final MeasuredText m =
        measurer.measure('Invoice', const JetTextStyle(fontSize: 24));
    final Uint8List logo = await _solidPng(10, 10, 0xFF3366CC);

    const PageFormat page =
        PageFormat(width: 120, height: 60, margins: JetEdgeInsets.all(0));
    final PageFrame frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 120, height: 60),
              fill: JetColor(0xFFFFFFFF)))
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 6, y: 8, width: 110, height: 30),
              lines: m.lines,
              style: const JetTextStyle(fontSize: 24),
              fontFamily: reg.resolveFamily(null)))
          ..add(ImagePrimitive(
              bounds: const JetRect(x: 96, y: 6, width: 18, height: 18),
              bytes: logo,
              fit: JetBoxFit.contain))
          ..add(const LinePrimitive(
              bounds: JetRect(x: 6, y: 44, width: 108, height: 0),
              start: JetOffset(6, 44),
              end: JetOffset(114, 44),
              color: JetColor.black,
              strokeWidth: 1)))
        .build();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), reg);
    await paintFrame(frame, painter);
    final ui.Image image = await recorder
        .endRecording()
        .toImage(page.width.toInt(), page.height.toInt());

    await expectLater(image, matchesGoldenFile('goldens/canvas_fixture.png'));
  });

  // --- 021 format properties: styled text (US1 / C11 / SC-002) -------------
  test(
      'paints a styled-text page (family, size, B/I/U, translucent color, '
      'alignments) to a golden', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    // A second family (same bytes under a distinct name) so a non-default
    // fontFamily flows through the full resolve/load path.
    reg.register('Display', reg.bytesFor(null));
    final MetricsTextMeasurer measurer = MetricsTextMeasurer(reg);

    const PageFormat page =
        PageFormat(width: 220, height: 180, margins: JetEdgeInsets.all(0));
    final FrameBuilder builder = FrameBuilder(page)
      ..add(const RectPrimitive(
          bounds: JetRect(x: 0, y: 0, width: 220, height: 180),
          fill: JetColor(0xFFFFFFFF)));

    void addRun(String text, JetTextStyle style, double y) {
      final MeasuredText m = measurer.measure(text, style,
          maxWidth: 200); // wrap long runs like the renderer would
      builder.add(TextRunPrimitive(
        bounds: JetRect(x: 10, y: y, width: 200, height: 24),
        lines: m.lines,
        style: style,
        fontFamily: reg.resolveFamily(style.fontFamily,
            weight: style.weight, italic: style.italic),
      ));
    }

    addRun('Display family',
        const JetTextStyle(fontFamily: 'Display', fontSize: 16), 6);
    addRun('Bold 18',
        const JetTextStyle(fontSize: 18, weight: JetFontWeight.bold), 30);
    addRun('Italic', const JetTextStyle(fontSize: 14, italic: true), 56);
    addRun('Underlined', const JetTextStyle(fontSize: 14, underline: true), 78);
    addRun(
        'Translucent underline',
        const JetTextStyle(
            fontSize: 14, underline: true, color: JetColor(0x801E40AF)),
        100);
    addRun('Left', const JetTextStyle(fontSize: 12, align: JetTextAlign.left),
        124);
    addRun('Center',
        const JetTextStyle(fontSize: 12, align: JetTextAlign.center), 142);
    addRun('Right', const JetTextStyle(fontSize: 12, align: JetTextAlign.right),
        160);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), reg);
    await paintFrame(builder.build(), painter);
    final ui.Image image = await recorder
        .endRecording()
        .toImage(page.width.toInt(), page.height.toInt());

    await expectLater(
        image, matchesGoldenFile('goldens/canvas_styled_text.png'));
  });

  // --- 021 format properties: shape styles (US2 / C7 / C11) ----------------
  test(
      'paints a shape-style page (filled+stroked, fill-only, stroke-only, '
      'none+none, width-0) to a golden', () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final RenderContext ctx = RenderContext(measurer: MetricsTextMeasurer(reg));
    const ShapeElementRenderer renderer = ShapeElementRenderer();

    const PageFormat page =
        PageFormat(width: 220, height: 120, margins: JetEdgeInsets.all(0));
    final FrameBuilder builder = FrameBuilder(page)
      ..add(const RectPrimitive(
          bounds: JetRect(x: 0, y: 0, width: 220, height: 120),
          fill: JetColor(0xFFFFFFFF)));

    // Each case goes THROUGH the real renderer so the golden pins the
    // stroke-width-0 seam, not hand-built primitives.
    void addShape(String id, double x, double y, JetBoxStyle style,
        {ShapeKind kind = ShapeKind.rectangle}) {
      final JetRect bounds = JetRect(x: x, y: y, width: 56, height: 36);
      renderer.emit(
        ShapeElement(id: id, bounds: bounds, kind: kind, style: style),
        ctx,
        bounds,
        builder,
      );
    }

    addShape(
        'filled-stroked',
        10,
        10,
        const JetBoxStyle(
            fill: JetColor(0x553B82F6),
            stroke: JetColor(0xFF1E40AF),
            strokeWidth: 2));
    addShape(
        'fill-only', 80, 10, const JetBoxStyle(fill: JetColor(0xFF22C55E)));
    addShape('stroke-only', 150, 10,
        const JetBoxStyle(stroke: JetColor(0xFFEF4444), strokeWidth: 3),
        kind: ShapeKind.hexagon);
    // None + none: nothing paints — the area stays blank (the canvas's
    // selectable affordance is designer chrome, not render output).
    addShape('none-none', 10, 70, JetBoxStyle.none);
    // Width 0: the outline disappears although the stroke color is stored.
    addShape(
        'width-0',
        80,
        70,
        const JetBoxStyle(
            fill: JetColor(0xFFF59E0B),
            stroke: JetColor(0xFF000000),
            strokeWidth: 0));

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), reg);
    await paintFrame(builder.build(), painter);
    final ui.Image image = await recorder
        .endRecording()
        .toImage(page.width.toInt(), page.height.toInt());

    await expectLater(
        image, matchesGoldenFile('goldens/canvas_shape_styles.png'));
  });
}
