// ChartElementRenderer: measure returns box; bar→RectPrimitives+LinePrimitives;
// line→PathPrimitive; pie→PathPrimitives per slice; empty series doesn't throw.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/chart_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/chart_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx = RenderContext(
      measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const ChartElementRenderer renderer = ChartElementRenderer();
  const JetRect bounds = JetRect(x: 0, y: 0, width: 200, height: 120);

  ChartElement chart(ChartType t) => ChartElement(
        id: 'c1',
        bounds: bounds,
        chartType: t,
        collectionField: 'm',
        valueExpression: r'$F{v}',
        points: const <ChartPoint>[
          ChartPoint('Jan', 10),
          ChartPoint('Feb', 20),
          ChartPoint('Mar', 30),
        ],
      );

  test('measure returns the element box', () {
    expect(
      renderer.measure(chart(ChartType.bar), ctx, const JetConstraints()),
      const JetSize(200, 120),
    );
  });

  test('bar: one RectPrimitive per point (plus axis chrome)', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(chart(ChartType.bar), ctx, bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    final Iterable<RectPrimitive> rects =
        prims.whereType<RectPrimitive>().where((r) => r.elementId == 'c1');
    expect(rects.length, greaterThanOrEqualTo(3));
    // value axis gridlines are present
    expect(prims.whereType<LinePrimitive>(), isNotEmpty);
  });

  test('line: emits a PathPrimitive polyline', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(chart(ChartType.line), ctx, bounds, out);
    expect(out.build().primitives.whereType<PathPrimitive>(), isNotEmpty);
  });

  test('pie: one PathPrimitive per slice', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(chart(ChartType.pie), ctx, bounds, out);
    expect(out.build().primitives.whereType<PathPrimitive>().length,
        greaterThanOrEqualTo(3));
  });

  test('empty series does not throw', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(
        const ChartElement(
            id: 'e',
            bounds: bounds,
            chartType: ChartType.bar,
            collectionField: 'm',
            valueExpression: r'$F{v}'),
        ctx,
        bounds,
        out);
    // no exception; may emit only chrome (axis lines / text)
  });
}
