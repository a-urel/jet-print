// JP0 spike: ChartPrimitive (jet_charts_core) -> FramePrimitive.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart' as core;
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/rendering/elements/chart/chart_frame_converter.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

core.Chart _chart(core.ChartKind kind) => core.Chart(
      kind: kind,
      title: const core.ChartTitle(text: 'Sales'),
      series: <core.ChartSeries>[
        core.ChartSeries(
          name: core.ChartData<String>(values: <String>['Revenue']),
          categories: core.ChartData<Object>(
              values: <Object>['Jan', 'Feb', 'Mar', 'Apr']),
          values: core.ChartData<double>(values: <double>[10, 25, 15, 30]),
        ),
      ],
    );

void main() {
  final MetricsTextMeasurer measurer =
      MetricsTextMeasurer(FontRegistry()..registerDefault());
  const JetRect bounds = JetRect(x: 40, y: 100, width: 300, height: 180);

  test('measurer adapter reports the engine width and height', () {
    final ChartEngineMeasurer m = ChartEngineMeasurer(measurer);
    final core.ChartTextStyle s = core.ChartTextStyle(
        fontFamily: '', size: 10, color: core.ChartColor.rgb(0));
    final core.ChartSize one = m.measure('Hello', s);
    final core.ChartSize two = m.measure('Hello\nHello', s);
    expect(one.width, greaterThan(0));
    expect(two.height, closeTo(one.height * 2, 0.001));
    expect(two.width, closeTo(one.width, 0.001));
  });

  test('column chart converts to rects, lines/paths and text, offset by bounds',
      () {
    final ChartFrameResult r = chartToFrame(
      _chart(core.ChartKind.column),
      bounds: bounds,
      measurer: measurer,
      elementId: 'c1',
    );
    expect(r.primitives.whereType<RectPrimitive>(), isNotEmpty);
    expect(r.primitives.whereType<TextRunPrimitive>(), isNotEmpty);
    for (final FramePrimitive p in r.primitives) {
      expect(p.elementId, 'c1');
      expect(p.bounds.x, greaterThanOrEqualTo(bounds.x - 0.001));
      expect(p.bounds.y, greaterThanOrEqualTo(bounds.y - 0.001));
      expect(p.bounds.x + p.bounds.width,
          lessThanOrEqualTo(bounds.x + bounds.width + 0.5));
    }
  });

  test('pie slices are real arcs, one closed path per slice', () {
    final ChartFrameResult r = chartToFrame(
      _chart(core.ChartKind.pie),
      bounds: bounds,
      measurer: measurer,
    );
    final List<PathPrimitive> slices = r.primitives
        .whereType<PathPrimitive>()
        .where((PathPrimitive p) => p.commands.any((c) => c is ArcTo))
        .toList();
    expect(slices, hasLength(4));
    for (final PathPrimitive p in slices) {
      expect(p.commands.first, isA<MoveTo>());
      expect(p.commands.last, isA<ClosePath>());
    }
  });

  test('line chart children carry the plot clip, inside the element', () {
    final ChartFrameResult r = chartToFrame(
      _chart(core.ChartKind.line),
      bounds: bounds,
      measurer: measurer,
    );
    final Iterable<FramePrimitive> clipped =
        r.primitives.where((FramePrimitive p) => p.clip != null);
    expect(clipped, isNotEmpty);
    for (final FramePrimitive p in clipped) {
      final JetRect c = p.clip!;
      expect(c.x, greaterThanOrEqualTo(bounds.x));
      expect(c.x + c.width, lessThanOrEqualTo(bounds.x + bounds.width + 0.001));
    }
  });

  test('fillOpacity becomes colour alpha; the stroke stays opaque', () {
    final List<FramePrimitive> out = convertChartPrimitives(
      <core.ChartPrimitive>[
        core.PathPrimitive(
          'p',
          <core.ChartPoint>[
            core.ChartPoint(0, 0),
            core.ChartPoint(10, 0),
            core.ChartPoint(10, 10),
          ],
          closed: true,
          fill: core.ChartColor.rgb(0x112233),
          stroke: core.ChartColor.rgb(0x445566),
          fillOpacity: 0.5,
        ),
      ],
      bounds: bounds,
      measurer: measurer,
    );
    final PathPrimitive p = out.single as PathPrimitive;
    expect(p.fill!.argb, 0x80112233);
    expect(p.stroke!.argb, 0xFF445566);
  });

  test('a core dash pattern becomes the frame dashPattern', () {
    final List<FramePrimitive> out = convertChartPrimitives(
      <core.ChartPrimitive>[
        core.PathPrimitive(
          'p',
          <core.ChartPoint>[core.ChartPoint(0, 0), core.ChartPoint(10, 0)],
          stroke: core.ChartColor.rgb(0),
          dash: <double>[4, 2],
        ),
      ],
      bounds: bounds,
      measurer: measurer,
    );
    expect((out.single as PathPrimitive).dashPattern, <double>[4, 2]);
  });

  test('a donut segment is outer arc, inner arc back, closed', () {
    final List<FramePrimitive> out = convertChartPrimitives(
      <core.ChartPrimitive>[
        core.ArcPrimitive('a', core.ChartPoint(50, 50), 40, 20, 0, 90,
            fill: core.ChartColor.rgb(0xFF0000)),
      ],
      bounds: bounds,
      measurer: measurer,
    );
    final List<PathCommand> c = (out.single as PathPrimitive).commands;
    expect(c.whereType<ArcTo>(), hasLength(2));
    expect(c.whereType<ArcTo>().last.sweepAngle,
        closeTo(-c.whereType<ArcTo>().first.sweepAngle, 1e-9),
        reason: 'the inner arc returns the way the outer one went');
  });
}
