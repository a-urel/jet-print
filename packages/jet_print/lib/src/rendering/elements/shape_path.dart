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
