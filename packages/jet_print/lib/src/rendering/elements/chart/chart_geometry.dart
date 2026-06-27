/// Pure-Dart chart geometry: turns a resolved series + a target box into bar
/// rects, a line polyline, or pie wedges plus a nice-number value axis. No
/// Flutter, no chart library, no text measurement — the single source the chart
/// renderer replays into frame primitives (so canvas/preview/export agree).
library;

import 'dart:math' as math;

import '../../../domain/elements/chart_element.dart';
import '../../../domain/geometry.dart';
import '../../frame/primitive.dart';

/// A nice-number value axis: the rounded-up [niceMax], the tick [step], and the
/// tick values from 0..niceMax inclusive.
class AxisScale {
  /// Creates an axis scale.
  const AxisScale(
      {required this.niceMax, required this.step, required this.ticks});

  /// The axis maximum (>= the data max), a whole multiple of [step].
  final double niceMax;

  /// The spacing between ticks.
  final double step;

  /// Tick values, 0..[niceMax] inclusive.
  final List<double> ticks;
}

/// A nice-number axis covering 0..[maxValue] in roughly [targetTicks] steps,
/// using the classic 1/2/5×10ⁿ ladder. Non-positive [maxValue] yields a safe
/// unit axis (so an all-zero or empty series still draws).
AxisScale niceAxis(double maxValue, {int targetTicks = 4}) {
  if (!(maxValue > 0)) {
    return const AxisScale(niceMax: 1, step: 1, ticks: <double>[0, 1]);
  }
  final double rawStep = maxValue / targetTicks;
  final double mag =
      math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final double norm = rawStep / mag;
  final double niceNorm =
      norm < 1.5 ? 1 : (norm < 3 ? 2 : (norm < 5.5 ? 5 : (norm < 7 ? 6 : 10)));
  final double step = niceNorm * mag;
  final double niceMax = (maxValue / step).ceil() * step;
  final List<double> ticks = <double>[];
  for (double v = 0; v <= niceMax + step * 1e-9; v += step) {
    ticks.add(v);
  }
  return AxisScale(niceMax: niceMax, step: step, ticks: ticks);
}

/// One bottom-aligned bar rect per point, scaled to [axis].niceMax within [plot].
List<JetRect> barRects(
  List<ChartPoint> pts,
  JetRect plot,
  AxisScale axis, {
  double gapRatio = 0.25,
}) {
  if (pts.isEmpty || axis.niceMax <= 0) return const <JetRect>[];
  final double slot = plot.width / pts.length;
  final double barW = slot * (1 - gapRatio);
  return <JetRect>[
    for (var i = 0; i < pts.length; i++)
      () {
        final double h =
            (pts[i].value.clamp(0, axis.niceMax).toDouble() / axis.niceMax) *
                plot.height;
        return JetRect(
          x: plot.x + i * slot + (slot - barW) / 2,
          y: plot.y + plot.height - h,
          width: barW,
          height: h,
        );
      }(),
  ];
}

/// One polyline vertex per point, at the slot centre and the value's height.
List<JetOffset> linePolyline(
    List<ChartPoint> pts, JetRect plot, AxisScale axis) {
  if (pts.isEmpty || axis.niceMax <= 0) return const <JetOffset>[];
  final double slot = plot.width / pts.length;
  return <JetOffset>[
    for (var i = 0; i < pts.length; i++)
      JetOffset(
        plot.x + (i + 0.5) * slot,
        plot.y +
            plot.height -
            (pts[i].value.clamp(0, axis.niceMax).toDouble() / axis.niceMax) *
                plot.height,
      ),
  ];
}

/// A wedge of a pie. [commands] is a closed path (centre → arc → close).
class PieSlice {
  /// Creates a slice.
  const PieSlice({
    required this.commands,
    required this.startAngle,
    required this.sweepAngle,
    required this.value,
    required this.index,
  });

  /// The closed wedge path.
  final List<PathCommand> commands;

  /// Start angle (radians; -pi/2 is the top).
  final double startAngle;

  /// Sweep (radians), proportional to the value share.
  final double sweepAngle;

  /// The slice's value.
  final double value;

  /// The slice's index in the series (drives palette colour).
  final int index;
}

/// One wedge per positive-valued point, summing to a full circle, inscribed in
/// [box]. Non-positive values are dropped (a pie of a negative share is undefined).
List<PieSlice> pieSlices(List<ChartPoint> pts, JetRect box,
    {int arcSegments = 24}) {
  final List<ChartPoint> pos = <ChartPoint>[
    for (final ChartPoint p in pts)
      if (p.value > 0) p,
  ];
  final double total =
      pos.fold<double>(0, (double s, ChartPoint p) => s + p.value);
  if (total <= 0) return const <PieSlice>[];
  final double cx = box.x + box.width / 2;
  final double cy = box.y + box.height / 2;
  final double r = math.min(box.width, box.height) / 2;
  final List<PieSlice> out = <PieSlice>[];
  double start = -math.pi / 2;
  for (var i = 0; i < pos.length; i++) {
    final double sweep = (pos[i].value / total) * 2 * math.pi;
    final List<PathCommand> cmds = <PathCommand>[MoveTo(JetOffset(cx, cy))];
    for (var s = 0; s <= arcSegments; s++) {
      final double a = start + sweep * (s / arcSegments);
      cmds.add(LineTo(JetOffset(cx + r * math.cos(a), cy + r * math.sin(a))));
    }
    cmds.add(const ClosePath());
    out.add(PieSlice(
      commands: cmds,
      startAngle: start,
      sweepAngle: sweep,
      value: pos[i].value,
      index: i,
    ));
    start += sweep;
  }
  return out;
}
