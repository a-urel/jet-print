/// The single geometry source for the closed shape forms (020).
///
/// `shapePath(kind, bounds)` returns a **closed** polygon inscribed in [bounds]
/// — `MoveTo(v0)`, a `LineTo` per remaining vertex, then `ClosePath`. It is the
/// one place a form's shape is defined: the renderer emits it as a
/// `PathPrimitive` (so canvas, preview, and export share it) and the designer's
/// gallery thumbnail paints through it (so the picker icon cannot drift from the
/// rendered result). [ShapeKind.line] and [ShapeKind.rectangle] are NOT routed
/// here — the renderer keeps their dedicated `LinePrimitive`/`RectPrimitive`.
library;

import 'dart:math' as math;

import '../../domain/elements/shape_element.dart';
import '../../domain/geometry.dart';
import '../frame/primitive.dart';

/// The number of straight segments approximating an ellipse. A 64-gon is
/// visually smooth at report point sizes and at typical export DPI while reusing
/// the existing `LineTo` replay, so no curve primitive (and no new painter code)
/// is needed. A single tunable: raise it only if a fidelity issue is observed.
const int kEllipseSegments = 64;

/// Block-arrow shaft thickness as a fraction of the cross-axis (the box
/// dimension perpendicular to the arrow). 0.50 = the classic office look.
const double kArrowShaftRatio = 0.50;

/// Block-arrow head length as a fraction of the long-axis (the box dimension
/// along the arrow's direction).
const double kArrowHeadRatio = 0.45;

/// Chevron band thickness as a fraction of the long-axis (the box width, since
/// the chevron points right).
const double kChevronThicknessRatio = 0.50;

/// Rounded-rect corner radius as a fraction of the box's shorter side. Clamped
/// so the radius never exceeds half the shorter side (a fully-rounded "stadium"
/// at the limit, never an overshoot).
const double kRoundRectRadiusRatio = 0.20;

/// Straight segments approximating each quarter-circle corner of a [roundRect].
/// 8 is visually smooth at report point sizes while reusing the LineTo replay,
/// so no curve primitive is needed (same rationale as [kEllipseSegments]).
const int kCornerSegments = 8;

/// The straight angle quarter turn that puts a regular polygon's first vertex at
/// the top centre (a "point-up" orientation): screen `y` grows downward, so the
/// top is at angle −90°.
const double _kPointUp = -math.pi / 2;

/// Returns the closed inscribed polygon for [kind] within [bounds].
///
/// Every vertex lies on or inside [bounds], so changing a shape's form never
/// moves or resizes it. Degenerate-safe: a 1×1 or 1×N box yields a valid
/// (collapsed) closed path rather than throwing — painting a zero-area path is a
/// no-op. [ShapeKind.line]/[ShapeKind.rectangle] are handled by the renderer and
/// must not be passed here.
List<PathCommand> shapePath(ShapeKind kind, JetRect bounds) {
  final double cx = bounds.x + bounds.width / 2;
  final double cy = bounds.y + bounds.height / 2;
  final double rx = bounds.width / 2;
  final double ry = bounds.height / 2;

  final List<JetOffset> vertices = switch (kind) {
    ShapeKind.ellipse =>
      _regularPolygon(cx, cy, rx, ry, kEllipseSegments, startAngle: 0),
    ShapeKind.triangle => <JetOffset>[
        JetOffset(cx, bounds.y), // apex, top-centre
        JetOffset(bounds.x + bounds.width, bounds.y + bounds.height), // BR
        JetOffset(bounds.x, bounds.y + bounds.height), // BL
      ],
    ShapeKind.diamond => <JetOffset>[
        JetOffset(cx, bounds.y), // top
        JetOffset(bounds.x + bounds.width, cy), // right
        JetOffset(cx, bounds.y + bounds.height), // bottom
        JetOffset(bounds.x, cy), // left
      ],
    ShapeKind.pentagon => _regularPolygon(cx, cy, rx, ry, 5),
    ShapeKind.hexagon => _regularPolygon(cx, cy, rx, ry, 6),
    ShapeKind.star => _star(cx, cy, rx, ry, points: 5, innerRatio: 0.5),
    ShapeKind.arrowRight => () {
        final double shaftHalf = bounds.height * kArrowShaftRatio / 2;
        final double headW = bounds.width * kArrowHeadRatio;
        final double baseX = bounds.x + bounds.width - headW;
        final double left = bounds.x;
        final double right = bounds.x + bounds.width;
        final double top = bounds.y;
        final double bottom = bounds.y + bounds.height;
        return <JetOffset>[
          JetOffset(left, cy - shaftHalf),
          JetOffset(baseX, cy - shaftHalf),
          JetOffset(baseX, top),
          JetOffset(right, cy),
          JetOffset(baseX, bottom),
          JetOffset(baseX, cy + shaftHalf),
          JetOffset(left, cy + shaftHalf),
        ];
      }(),
    ShapeKind.arrowLeft => () {
        final double shaftHalf = bounds.height * kArrowShaftRatio / 2;
        final double headW = bounds.width * kArrowHeadRatio;
        final double baseX = bounds.x + headW;
        final double left = bounds.x;
        final double right = bounds.x + bounds.width;
        final double top = bounds.y;
        final double bottom = bounds.y + bounds.height;
        return <JetOffset>[
          JetOffset(right, cy - shaftHalf),
          JetOffset(baseX, cy - shaftHalf),
          JetOffset(baseX, top),
          JetOffset(left, cy),
          JetOffset(baseX, bottom),
          JetOffset(baseX, cy + shaftHalf),
          JetOffset(right, cy + shaftHalf),
        ];
      }(),
    ShapeKind.arrowUp => () {
        final double shaftHalf = bounds.width * kArrowShaftRatio / 2;
        final double headH = bounds.height * kArrowHeadRatio;
        final double baseY = bounds.y + headH;
        final double left = bounds.x;
        final double right = bounds.x + bounds.width;
        final double top = bounds.y;
        final double bottom = bounds.y + bounds.height;
        return <JetOffset>[
          JetOffset(cx - shaftHalf, bottom),
          JetOffset(cx - shaftHalf, baseY),
          JetOffset(left, baseY),
          JetOffset(cx, top),
          JetOffset(right, baseY),
          JetOffset(cx + shaftHalf, baseY),
          JetOffset(cx + shaftHalf, bottom),
        ];
      }(),
    ShapeKind.arrowDown => () {
        final double shaftHalf = bounds.width * kArrowShaftRatio / 2;
        final double headH = bounds.height * kArrowHeadRatio;
        final double baseY = bounds.y + bounds.height - headH;
        final double left = bounds.x;
        final double right = bounds.x + bounds.width;
        final double top = bounds.y;
        final double bottom = bounds.y + bounds.height;
        return <JetOffset>[
          JetOffset(cx - shaftHalf, top),
          JetOffset(cx - shaftHalf, baseY),
          JetOffset(left, baseY),
          JetOffset(cx, bottom),
          JetOffset(right, baseY),
          JetOffset(cx + shaftHalf, baseY),
          JetOffset(cx + shaftHalf, top),
        ];
      }(),
    ShapeKind.arrowDouble => () {
        final double shaftHalf = bounds.height * kArrowShaftRatio / 2;
        final double headW = bounds.width * kArrowHeadRatio;
        final double leftBase = bounds.x + headW;
        final double rightBase = bounds.x + bounds.width - headW;
        final double left = bounds.x;
        final double right = bounds.x + bounds.width;
        final double top = bounds.y;
        final double bottom = bounds.y + bounds.height;
        return <JetOffset>[
          JetOffset(left, cy),
          JetOffset(leftBase, top),
          JetOffset(leftBase, cy - shaftHalf),
          JetOffset(rightBase, cy - shaftHalf),
          JetOffset(rightBase, top),
          JetOffset(right, cy),
          JetOffset(rightBase, bottom),
          JetOffset(rightBase, cy + shaftHalf),
          JetOffset(leftBase, cy + shaftHalf),
          JetOffset(leftBase, bottom),
        ];
      }(),
    ShapeKind.chevron => () {
        final double t = bounds.width * kChevronThicknessRatio;
        final double left = bounds.x;
        final double right = bounds.x + bounds.width;
        final double top = bounds.y;
        final double bottom = bounds.y + bounds.height;
        return <JetOffset>[
          JetOffset(left, top),
          JetOffset(right, cy),
          JetOffset(left, bottom),
          JetOffset(left + t, bottom),
          JetOffset(right - t, cy),
          JetOffset(left + t, top),
        ];
      }(),
    ShapeKind.roundRect => _roundRect(bounds),
    // line/rectangle are special-cased by the renderer and never reach here.
    ShapeKind.line || ShapeKind.rectangle => <JetOffset>[
        JetOffset(bounds.x, bounds.y),
        JetOffset(bounds.x + bounds.width, bounds.y + bounds.height),
      ],
  };

  return <PathCommand>[
    MoveTo(vertices.first),
    for (final JetOffset v in vertices.skip(1)) LineTo(v),
    const ClosePath(),
  ];
}

/// [count] equally-spaced vertices on the ellipse inscribed in the bounds,
/// starting at [startAngle] (default point-up) and stepping clockwise.
List<JetOffset> _regularPolygon(
  double cx,
  double cy,
  double rx,
  double ry,
  int count, {
  double startAngle = _kPointUp,
}) {
  final double step = 2 * math.pi / count;
  return <JetOffset>[
    for (int i = 0; i < count; i++)
      JetOffset(
        cx + rx * math.cos(startAngle + i * step),
        cy + ry * math.sin(startAngle + i * step),
      ),
  ];
}

/// The closed corner-fan polygon for a rounded rectangle inscribed in [bounds].
///
/// Each of the four corners is a quarter-circle of [kCornerSegments] `+1`
/// sampled points; the straight edges are the `LineTo`s between adjacent
/// corners. Radius is clamped to half the shorter side so a thin box collapses
/// to a valid (non-overshooting) path rather than self-intersecting.
List<JetOffset> _roundRect(JetRect bounds) {
  final double left = bounds.x;
  final double top = bounds.y;
  final double right = bounds.x + bounds.width;
  final double bottom = bounds.y + bounds.height;
  final double shorter = math.min(bounds.width, bounds.height);
  final double r = math.min(kRoundRectRadiusRatio * shorter, shorter / 2);

  // Corner arc centres and start angles (screen y grows downward, angles sweep
  // +90° clockwise). Order TL→TR→BR→BL yields a clockwise outline whose corner
  // ends meet the straight edges exactly.
  List<JetOffset> arc(double ccx, double ccy, double startAngle) => <JetOffset>[
        for (int i = 0; i <= kCornerSegments; i++)
          () {
            final double a = startAngle + (math.pi / 2) * (i / kCornerSegments);
            return JetOffset(ccx + r * math.cos(a), ccy + r * math.sin(a));
          }(),
      ];

  return <JetOffset>[
    ...arc(left + r, top + r, math.pi), // TL: 180°→270°
    ...arc(right - r, top + r, math.pi * 1.5), // TR: 270°→360°
    ...arc(right - r, bottom - r, 0), // BR: 0°→90°
    ...arc(left + r, bottom - r, math.pi / 2), // BL: 90°→180°
  ];
}

/// A point-up star: [points] outer vertices on the inscribed ellipse alternating
/// with inner vertices at [innerRatio] of the radius, so the path has
/// `2 * points` vertices.
List<JetOffset> _star(
  double cx,
  double cy,
  double rx,
  double ry, {
  required int points,
  required double innerRatio,
}) {
  final double step = math.pi / points; // half a full step between alternations
  return <JetOffset>[
    for (int i = 0; i < points * 2; i++)
      () {
        final double r = i.isEven ? 1.0 : innerRatio;
        final double a = _kPointUp + i * step;
        return JetOffset(cx + rx * r * math.cos(a), cy + ry * r * math.sin(a));
      }(),
  ];
}
