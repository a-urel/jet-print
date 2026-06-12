// Geometry unit tests for `shapePath` (020 / contract C6.1–C6.4).
//
// `shapePath(kind, bounds)` is the ONE source of geometry for the six new closed
// forms — consumed by both the renderer (canvas/preview/export) and the gallery
// thumbnail, so proving it here proves the picker can never drift from the
// rendered shape. Each form is a closed polygon inscribed in `bounds`:
// `MoveTo(v0)` … `LineTo(vN-1)` … `ClosePath`, every vertex on/inside the box.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/rendering/elements/shape_path.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

/// The ordered geometry points of [commands] — the `MoveTo` start plus every
/// `LineTo` target (a closed polygon's vertices, in order).
List<JetOffset> _points(List<PathCommand> commands) => <JetOffset>[
      for (final PathCommand c in commands)
        if (c is MoveTo) c.to else if (c is LineTo) c.to,
    ];

/// Euclidean distance between two geometry points (JetOffset is a pure value
/// type with no vector ops, so the test supplies its own).
double _dist(JetOffset a, JetOffset b) =>
    math.sqrt(math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2));

/// The six closed forms `shapePath` is responsible for, with their expected
/// inscribed-polygon vertex counts (the renderer special-cases line/rectangle,
/// so they are NOT routed through `shapePath`).
const Map<ShapeKind, int> _vertexCount = <ShapeKind, int>{
  ShapeKind.ellipse: 64,
  ShapeKind.triangle: 3,
  ShapeKind.diamond: 4,
  ShapeKind.pentagon: 5,
  ShapeKind.hexagon: 6,
  ShapeKind.star: 10,
};

void main() {
  const JetRect bounds = JetRect(x: 10, y: 20, width: 80, height: 60);
  const double left = 10, top = 20, right = 90, bottom = 80;
  const double cx = 50, cy = 50; // centre
  const double eps = 1e-9;

  group('C6.1 — closed inscribed polygon shape', () {
    for (final MapEntry<ShapeKind, int> form in _vertexCount.entries) {
      test(
          '${form.key.name} starts with MoveTo, ends with ClosePath, '
          'has ${form.value} vertices', () {
        final List<PathCommand> cmds = shapePath(form.key, bounds);
        expect(cmds.first, isA<MoveTo>(),
            reason: 'a closed sub-path opens with a MoveTo');
        expect(cmds.last, isA<ClosePath>(),
            reason: 'a closed sub-path ends with ClosePath');
        // Exactly one MoveTo, then (n-1) LineTo, then ClosePath.
        expect(cmds.whereType<MoveTo>(), hasLength(1));
        expect(cmds.whereType<LineTo>(), hasLength(form.value - 1));
        expect(_points(cmds), hasLength(form.value),
            reason: '${form.key.name} has ${form.value} vertices');
      });
    }
  });

  group('C6.2 — every vertex lies within (or on) the bounds box', () {
    for (final ShapeKind kind in _vertexCount.keys) {
      test('${kind.name} vertices are inside the box', () {
        for (final JetOffset v in _points(shapePath(kind, bounds))) {
          expect(v.dx, inInclusiveRange(left - eps, right + eps));
          expect(v.dy, inInclusiveRange(top - eps, bottom + eps));
        }
      });
    }
  });

  group('C6.3 — point-up, equilateral regular polygons on square bounds', () {
    const JetRect square = JetRect(x: 0, y: 0, width: 100, height: 100);

    test('triangle apex is top-centre, base on the bottom edge', () {
      final List<JetOffset> v = _points(shapePath(ShapeKind.triangle, bounds));
      expect(v[0].dx, closeTo(cx, eps)); // apex centred
      expect(v[0].dy, closeTo(top, eps)); // apex on top edge
      expect(v[1].dy, closeTo(bottom, eps)); // base on bottom edge
      expect(v[2].dy, closeTo(bottom, eps));
    });

    test('diamond touches the four edge midpoints', () {
      final List<JetOffset> v = _points(shapePath(ShapeKind.diamond, bounds));
      expect(v, contains(const JetOffset(cx, top)));
      expect(v, contains(const JetOffset(right, cy)));
      expect(v, contains(const JetOffset(cx, bottom)));
      expect(v, contains(const JetOffset(left, cy)));
    });

    for (final ShapeKind kind in <ShapeKind>[
      ShapeKind.pentagon,
      ShapeKind.hexagon,
    ]) {
      test('${kind.name} is point-up and equilateral on square bounds', () {
        final List<JetOffset> v = _points(shapePath(kind, square));
        // Point-up: the first vertex sits at the top-centre.
        expect(v.first.dx, closeTo(50, 1e-6));
        expect(v.first.dy, closeTo(0, 1e-6));
        // Equilateral: every edge (including the closing one) is equal length.
        final List<double> edges = <double>[
          for (int i = 0; i < v.length; i++) _dist(v[(i + 1) % v.length], v[i]),
        ];
        for (final double e in edges) {
          expect(e, closeTo(edges.first, 1e-6),
              reason: 'all edges of a regular ${kind.name} are equal');
        }
      });
    }

    test('star alternates outer and inner radius at the 0.5 ratio', () {
      final List<JetOffset> v = _points(shapePath(ShapeKind.star, square));
      const JetOffset centre = JetOffset(50, 50);
      final List<double> radii = <double>[
        for (final JetOffset p in v) _dist(p, centre),
      ];
      // First vertex is an outer point at the top.
      expect(v.first.dx, closeTo(50, 1e-6));
      expect(v.first.dy, closeTo(0, 1e-6));
      // Outer radius 50 (even indices), inner radius 25 (odd indices).
      for (int i = 0; i < radii.length; i++) {
        expect(radii[i], closeTo(i.isEven ? 50 : 25, 1e-6));
      }
    });
  });

  group('C6.4 — degenerate bounds never throw', () {
    for (final ShapeKind kind in _vertexCount.keys) {
      test('${kind.name} on a 1×1 box yields a valid path', () {
        const JetRect dot = JetRect(x: 5, y: 5, width: 1, height: 1);
        expect(() => shapePath(kind, dot), returnsNormally);
        expect(shapePath(kind, dot).last, isA<ClosePath>());
      });

      test('${kind.name} on a 1×N sliver does not throw', () {
        const JetRect sliver = JetRect(x: 0, y: 0, width: 1, height: 40);
        expect(() => shapePath(kind, sliver), returnsNormally);
      });
    }
  });

  test('the ellipse uses kEllipseSegments points on the inscribed ellipse', () {
    expect(kEllipseSegments, 64);
    final List<JetOffset> v = _points(shapePath(ShapeKind.ellipse, bounds));
    expect(v, hasLength(kEllipseSegments));
    // Each point honours the inscribed-ellipse equation within float epsilon.
    for (final JetOffset p in v) {
      final double nx = (p.dx - cx) / 40; // rx = 40
      final double ny = (p.dy - cy) / 30; // ry = 30
      expect(nx * nx + ny * ny, closeTo(1.0, 1e-6));
    }
    // The first point is on the +x axis (θ = 0), a stable, documented start.
    expect(v.first.dx, closeTo(right, 1e-6));
    expect(v.first.dy, closeTo(cy, 1e-6));
    // Sanity: a known mid-quadrant angle lands where math says it should.
    const double theta = 2 * math.pi / kEllipseSegments;
    expect(v[1].dx, closeTo(cx + 40 * math.cos(theta), 1e-6));
    expect(v[1].dy, closeTo(cy + 30 * math.sin(theta), 1e-6));
  });
}
