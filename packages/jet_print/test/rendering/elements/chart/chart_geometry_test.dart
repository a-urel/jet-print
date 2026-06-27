// test/rendering/elements/chart/chart_geometry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/elements/chart/chart_geometry.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

void main() {
  group('niceAxis', () {
    test('rounds the max up to a nice multiple', () {
      final a = niceAxis(23);
      expect(a.niceMax, 24); // step 6, ceil(23/6)*6
      expect(a.step, 6);
      expect(a.ticks, <double>[0, 6, 12, 18, 24]);
    });
    test('non-positive max is safe', () {
      expect(niceAxis(0).niceMax, greaterThan(0));
      expect(niceAxis(-5).niceMax, greaterThan(0));
    });
  });

  test('barRects: one rect per point, scaled to niceMax, inside the plot', () {
    const plot = JetRect(x: 10, y: 10, width: 100, height: 50);
    final axis = niceAxis(10); // niceMax 10
    final rects = barRects(
        const <ChartPoint>[ChartPoint('a', 5), ChartPoint('b', 10)],
        plot,
        axis);
    expect(rects, hasLength(2));
    expect(rects[0].height, closeTo(25, 1e-9)); // 5/10 * 50
    expect(rects[1].height, closeTo(50, 1e-9)); // full
    // bottom-aligned to the plot's bottom edge
    expect(rects[1].y + rects[1].height, closeTo(plot.y + plot.height, 1e-9));
    // within horizontal bounds
    expect(rects[0].x, greaterThanOrEqualTo(plot.x));
  });

  test('linePolyline: one point per series point at the value height', () {
    const plot = JetRect(x: 0, y: 0, width: 100, height: 40);
    final pts = linePolyline(
        const <ChartPoint>[ChartPoint('a', 0), ChartPoint('b', 20)],
        plot,
        niceAxis(20));
    expect(pts, hasLength(2));
    expect(pts[0].dy, closeTo(40, 1e-9)); // value 0 → bottom
    expect(pts[1].dy, closeTo(0, 1e-9)); // value 20 (=niceMax) → top
  });

  group('pieSlices', () {
    const box = JetRect(x: 0, y: 0, width: 100, height: 100);
    test('sweep angles sum to 2*pi and split by value share', () {
      final slices = pieSlices(
          const <ChartPoint>[ChartPoint('a', 1), ChartPoint('b', 3)], box);
      expect(slices, hasLength(2));
      final total = slices.fold<double>(0, (s, x) => s + x.sweepAngle);
      expect(total, closeTo(2 * 3.141592653589793, 1e-6));
      expect(slices[1].sweepAngle, closeTo(3 * slices[0].sweepAngle, 1e-6));
    });
    test('each slice is a closed path (MoveTo .. ClosePath)', () {
      final s = pieSlices(const <ChartPoint>[ChartPoint('a', 1)], box).single;
      expect(s.commands.first, isA<MoveTo>());
      expect(s.commands.last, isA<ClosePath>());
    });
  });

  test('empty series → empty geometry, no throw', () {
    const plot = JetRect(x: 0, y: 0, width: 10, height: 10);
    expect(barRects(const <ChartPoint>[], plot, niceAxis(1)), isEmpty);
    expect(pieSlices(const <ChartPoint>[], plot), isEmpty);
  });
}
