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

  test('pie arcs are flattened to closed paths, none dropped', () {
    final ChartFrameResult r = chartToFrame(
      _chart(core.ChartKind.pie),
      bounds: bounds,
      measurer: measurer,
    );
    expect(r.gaps.arcsFlattened, greaterThan(0));
    final Iterable<PathPrimitive> paths =
        r.primitives.whereType<PathPrimitive>();
    expect(paths.length, greaterThanOrEqualTo(r.gaps.arcsFlattened));
    for (final PathPrimitive p in paths) {
      expect(p.commands.first, isA<MoveTo>());
    }
  });

  test('line chart counts what the frame cannot express, not hides it', () {
    final ChartFrameResult r = chartToFrame(
      _chart(core.ChartKind.line),
      bounds: bounds,
      measurer: measurer,
    );
    expect(r.gaps.clipsDropped, greaterThan(0));
    expect(r.gaps.arcsFlattened, greaterThan(0)); // the point markers
  });
}
