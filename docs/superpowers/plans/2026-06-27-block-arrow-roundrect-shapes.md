# Block Arrow & Rounded-Rectangle Shapes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add seven new closed shape forms (six block arrows + a rounded rectangle) to `ShapeKind`, drawn through the existing `shapePath` single-geometry-source.

**Architecture:** Each form is an inscribed closed polygon (`MoveTo` → `LineTo`… → `ClosePath`) returned by `shapePath(kind, bounds)`, consumed by both the renderer (`PathPrimitive`) and the designer gallery thumbnail. Arrows are explicit per-direction vertex lists; the rounded rect approximates each corner with a fan of `LineTo` steps (same pattern as the ellipse 64-gon). No new path command, no painter change, no codec change.

**Tech Stack:** Dart / Flutter, `flutter_test`, golden tests. Package root: `packages/jet_print`.

## Global Constraints

- Forms serialize by enum `name` — no schema bump, additive only. Existing-form goldens must stay **byte-identical**.
- `line` and `rectangle` keep their dedicated `LinePrimitive`/`RectPrimitive`; all new forms route through the shared closed-form `PathPrimitive` branch.
- Arrows **stretch with bounds** (ratios relative to width/height); no fixed-aspect resize logic.
- Geometry constants live in `packages/jet_print/lib/src/rendering/elements/shape_path.dart` beside `kEllipseSegments` (no scattered magic numbers).
- Run all test commands from `packages/jet_print` (the package root), e.g. `cd packages/jet_print && flutter test …`.
- New `ShapeKind` value order is irrelevant to the wire format; append after `star` to keep diffs minimal.
- l10n: every new `shapeForm<X>` getter must be declared in the abstract base (`jet_print_localizations.dart`) AND implemented in en/tr/de, or the package will not compile.

---

## Task 1: Add the seven `ShapeKind` enum values

**Files:**
- Modify: `packages/jet_print/lib/src/domain/elements/shape_element.dart` (the `enum ShapeKind`, ends at line 43)
- Test: `packages/jet_print/test/domain/elements/shape_element_test.dart`

**Interfaces:**
- Produces: `ShapeKind.arrowRight`, `ShapeKind.arrowLeft`, `ShapeKind.arrowUp`, `ShapeKind.arrowDown`, `ShapeKind.arrowDouble`, `ShapeKind.chevron`, `ShapeKind.roundRect` — new enum values consumed by every later task.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/domain/elements/shape_element_test.dart`:

```dart
group('new forms (block arrows + rounded rect)', () {
  test('the seven new ShapeKind values exist and serialize by name', () {
    const List<ShapeKind> added = <ShapeKind>[
      ShapeKind.arrowRight,
      ShapeKind.arrowLeft,
      ShapeKind.arrowUp,
      ShapeKind.arrowDown,
      ShapeKind.arrowDouble,
      ShapeKind.chevron,
      ShapeKind.roundRect,
    ];
    expect(added.map((ShapeKind k) => k.name), <String>[
      'arrowRight',
      'arrowLeft',
      'arrowUp',
      'arrowDown',
      'arrowDouble',
      'chevron',
      'roundRect',
    ]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/domain/elements/shape_element_test.dart`
Expected: FAIL — compile error, `arrowRight` (etc.) not defined on `ShapeKind`.

- [ ] **Step 3: Add the enum values**

In `lib/src/domain/elements/shape_element.dart`, replace the closing of the enum (the `star` value plus its `}`):

```dart
  /// A five-point, point-up star inscribed in the bounds.
  star,
```

with:

```dart
  /// A five-point, point-up star inscribed in the bounds.
  star,

  /// A right-pointing block arrow: a horizontal shaft ending in a triangular
  /// head at the right edge.
  arrowRight,

  /// A left-pointing block arrow (the [arrowRight] form mirrored on X).
  arrowLeft,

  /// An up-pointing block arrow: a vertical shaft ending in a triangular head
  /// at the top edge.
  arrowUp,

  /// A down-pointing block arrow (the [arrowUp] form mirrored on Y).
  arrowDown,

  /// A two-headed horizontal block arrow: triangular heads at both the left and
  /// right edges joined by a central shaft.
  arrowDouble,

  /// A right-pointing chevron: a constant-thickness ">"-band with no tail.
  chevron,

  /// A rectangle with rounded corners (each corner approximated by a fan of
  /// straight segments, like the ellipse — no curve primitive needed).
  roundRect,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/domain/elements/shape_element_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/elements/shape_element.dart packages/jet_print/test/domain/elements/shape_element_test.dart
git commit -m "feat(shape): add block-arrow + roundRect ShapeKind values"
```

---

## Task 2: Geometry — block arrows in `shapePath`

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/elements/shape_path.dart` (add constants; extend the `switch` at lines 42-64)
- Test: `packages/jet_print/test/rendering/elements/shape_path_test.dart`

**Interfaces:**
- Consumes: `ShapeKind.arrowRight/arrowLeft/arrowUp/arrowDown/arrowDouble/chevron` (Task 1).
- Produces: `shapePath(kind, bounds)` returns the closed inscribed polygon for each arrow form (used by renderer Task 4 and gallery Task 5). New constants: `kArrowShaftRatio = 0.50`, `kArrowHeadRatio = 0.45`, `kChevronThicknessRatio = 0.50`.

Reference frame (matches the existing code): `left = bounds.x`, `top = bounds.y`, `right = bounds.x + bounds.width`, `bottom = bounds.y + bounds.height`, `cx`/`cy` the centre. Vertex counts: arrowRight/Left/Up/Down = **7**, arrowDouble = **10**, chevron = **6**.

- [ ] **Step 1: Write the failing tests**

In `test/rendering/elements/shape_path_test.dart`, add the new arrow forms to the `_vertexCount` map (insert before the closing `};`):

```dart
  ShapeKind.arrowRight: 7,
  ShapeKind.arrowLeft: 7,
  ShapeKind.arrowUp: 7,
  ShapeKind.arrowDown: 7,
  ShapeKind.arrowDouble: 10,
  ShapeKind.chevron: 6,
```

Then add a dedicated group inside `main()` (the C6.1 loop already asserts open/close/vertex-count/inside-bounds for every `_vertexCount` entry; this group pins the tips):

```dart
  group('block arrow tips sit on the pointed edge', () {
    test('arrowRight tip is at the right-edge vertical centre', () {
      final List<JetOffset> p = _points(shapePath(ShapeKind.arrowRight, bounds));
      expect(p.any((JetOffset v) => (v.dx - right).abs() < eps && (v.dy - cy).abs() < eps), isTrue);
    });
    test('arrowLeft tip is at the left-edge vertical centre', () {
      final List<JetOffset> p = _points(shapePath(ShapeKind.arrowLeft, bounds));
      expect(p.any((JetOffset v) => (v.dx - left).abs() < eps && (v.dy - cy).abs() < eps), isTrue);
    });
    test('arrowUp tip is at the top-edge horizontal centre', () {
      final List<JetOffset> p = _points(shapePath(ShapeKind.arrowUp, bounds));
      expect(p.any((JetOffset v) => (v.dx - cx).abs() < eps && (v.dy - top).abs() < eps), isTrue);
    });
    test('arrowDown tip is at the bottom-edge horizontal centre', () {
      final List<JetOffset> p = _points(shapePath(ShapeKind.arrowDown, bounds));
      expect(p.any((JetOffset v) => (v.dx - cx).abs() < eps && (v.dy - bottom).abs() < eps), isTrue);
    });
    test('arrowDouble has both left and right tips at vertical centre', () {
      final List<JetOffset> p = _points(shapePath(ShapeKind.arrowDouble, bounds));
      expect(p.any((JetOffset v) => (v.dx - left).abs() < eps && (v.dy - cy).abs() < eps), isTrue);
      expect(p.any((JetOffset v) => (v.dx - right).abs() < eps && (v.dy - cy).abs() < eps), isTrue);
    });
    test('chevron tip is at the right-edge vertical centre', () {
      final List<JetOffset> p = _points(shapePath(ShapeKind.chevron, bounds));
      expect(p.any((JetOffset v) => (v.dx - right).abs() < eps && (v.dy - cy).abs() < eps), isTrue);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/rendering/elements/shape_path_test.dart`
Expected: FAIL — the `switch` in `shapePath` is not exhaustive / returns the line-rectangle fallback for the new kinds, so vertex counts and tips are wrong.

- [ ] **Step 3: Add the ratio constants**

In `lib/src/rendering/elements/shape_path.dart`, after the `kEllipseSegments` declaration (line 22), add:

```dart
/// Block-arrow shaft thickness as a fraction of the cross-axis (the box
/// dimension perpendicular to the arrow). 0.50 = the classic office look.
const double kArrowShaftRatio = 0.50;

/// Block-arrow head length as a fraction of the long-axis (the box dimension
/// along the arrow's direction).
const double kArrowHeadRatio = 0.45;

/// Chevron band thickness as a fraction of the long-axis (the box width, since
/// the chevron points right).
const double kChevronThicknessRatio = 0.50;
```

- [ ] **Step 4: Add the arrow vertex lists to the switch**

In `shapePath`, the `switch (kind)` currently has cases through `ShapeKind.star` then a combined `line || rectangle` fallback. Add the six arrow cases **before** the `line || rectangle` case. Insert after the `ShapeKind.star =>` line (line 58):

```dart
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
```

Note: `roundRect` is added in Task 3; until then the `switch` is non-exhaustive for it. That is fine — Task 3 follows immediately and the analyzer error is expected between tasks. (If running tasks out of order, do Task 2 and Task 3 together before analyzing.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/rendering/elements/shape_path_test.dart`
Expected: PASS for all arrow/chevron tests. (A non-exhaustive-switch analyzer warning for `roundRect` may appear but the arrow tests run.)

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/lib/src/rendering/elements/shape_path.dart packages/jet_print/test/rendering/elements/shape_path_test.dart
git commit -m "feat(shape): block-arrow + chevron geometry in shapePath"
```

---

## Task 3: Geometry — rounded rectangle in `shapePath`

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/elements/shape_path.dart`
- Test: `packages/jet_print/test/rendering/elements/shape_path_test.dart`

**Interfaces:**
- Consumes: `ShapeKind.roundRect` (Task 1).
- Produces: `shapePath(ShapeKind.roundRect, bounds)` returns a `4 * (kCornerSegments + 1)`-vertex closed polygon approximating a rounded rectangle. New constants: `kRoundRectRadiusRatio = 0.20`, `kCornerSegments = 8`. Vertex count at default = `4 * 9 = 36`.

- [ ] **Step 1: Write the failing tests**

In `test/rendering/elements/shape_path_test.dart`, add `roundRect` to the `_vertexCount` map:

```dart
  ShapeKind.roundRect: 4 * (kCornerSegments + 1),
```

(`kCornerSegments` is imported from `shape_path.dart`, already imported in this test.)

Then add a group inside `main()`:

```dart
  group('roundRect corners', () {
    test('all vertices lie inside the bounds box', () {
      final List<JetOffset> p = _points(shapePath(ShapeKind.roundRect, bounds));
      for (final JetOffset v in p) {
        expect(v.dx, inInclusiveRange(left - eps, right + eps));
        expect(v.dy, inInclusiveRange(top - eps, bottom + eps));
      }
    });
    test('radius clamps on a thin box (no overshoot)', () {
      const JetRect thin = JetRect(x: 0, y: 0, width: 100, height: 4);
      final List<JetOffset> p = _points(shapePath(ShapeKind.roundRect, thin));
      for (final JetOffset v in p) {
        expect(v.dy, inInclusiveRange(-eps, 4 + eps));
      }
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/rendering/elements/shape_path_test.dart`
Expected: FAIL — `roundRect` not yet handled by `shapePath` (wrong vertex count / fallback path).

- [ ] **Step 3: Add the corner-segments constant + radius ratio**

In `lib/src/rendering/elements/shape_path.dart`, after the `kChevronThicknessRatio` constant added in Task 2, add:

```dart
/// Rounded-rect corner radius as a fraction of the box's shorter side. Clamped
/// so the radius never exceeds half the shorter side (a fully-rounded "stadium"
/// at the limit, never an overshoot).
const double kRoundRectRadiusRatio = 0.20;

/// Straight segments approximating each quarter-circle corner of a [roundRect].
/// 8 is visually smooth at report point sizes while reusing the LineTo replay,
/// so no curve primitive is needed (same rationale as [kEllipseSegments]).
const int kCornerSegments = 8;
```

- [ ] **Step 4: Add the `roundRect` case + corner-fan helper**

Add the `roundRect` case in the `switch` (after the `chevron` case, before `line || rectangle`):

```dart
    ShapeKind.roundRect => _roundRect(bounds),
```

Then add this helper at the end of the file (after `_star`):

```dart
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/rendering/elements/shape_path_test.dart`
Expected: PASS (all forms, including the C6.1 loop now covering roundRect's 36 vertices).

- [ ] **Step 6: Verify the analyzer is clean (switch now exhaustive)**

Run: `cd packages/jet_print && dart analyze lib/src/rendering/elements/shape_path.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add packages/jet_print/lib/src/rendering/elements/shape_path.dart packages/jet_print/test/rendering/elements/shape_path_test.dart
git commit -m "feat(shape): rounded-rectangle corner-fan geometry in shapePath"
```

---

## Task 4: Route the new forms through the renderer

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/elements/renderers/shape_element_renderer.dart` (the closed-form `case` group, lines 66-71)
- Test: `packages/jet_print/test/rendering/elements/shape_element_renderer_test.dart`

**Interfaces:**
- Consumes: the seven new `ShapeKind` values (Task 1) and `shapePath` (Tasks 2-3).
- Produces: each new form emits a single `PathPrimitive` from `shapePath` (canvas/preview/export parity).

- [ ] **Step 1: Write the failing test**

Add inside `main()` in `test/rendering/elements/shape_element_renderer_test.dart` (mirrors the existing closed-form assertions; `ctx`, `bounds`, `renderer` are already set up in the file's `main`):

```dart
  group('block-arrow + roundRect forms emit a PathPrimitive', () {
    for (final ShapeKind kind in <ShapeKind>[
      ShapeKind.arrowRight,
      ShapeKind.arrowLeft,
      ShapeKind.arrowUp,
      ShapeKind.arrowDown,
      ShapeKind.arrowDouble,
      ShapeKind.chevron,
      ShapeKind.roundRect,
    ]) {
      test('${kind.name} emits a PathPrimitive (not Rect/Line)', () {
        final ShapeElement el = ShapeElement(
          id: 'p',
          bounds: bounds,
          kind: kind,
          style: const JetBoxStyle(
            fill: JetColor(0xFF7CB3F0),
            stroke: JetColor.black,
            strokeWidth: 2,
          ),
        );
        final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
        renderer.emit(el, ctx, bounds, out);
        final FramePrimitive p = out.build().primitives.single;
        expect(p, isA<PathPrimitive>());
        expect((p as PathPrimitive).commands, shapePath(kind, bounds));
      });
    }
  });
```

If the test file does not already import `shape_path.dart`, add at the top with the other imports:

```dart
import 'package:jet_print/src/rendering/elements/shape_path.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/rendering/elements/shape_element_renderer_test.dart`
Expected: FAIL — the renderer `switch` does not handle the new kinds (compile error: non-exhaustive switch, or the new cases are missing).

- [ ] **Step 3: Add the new kinds to the closed-form case group**

In `lib/src/rendering/elements/renderers/shape_element_renderer.dart`, the closed-form group currently reads:

```dart
      case ShapeKind.ellipse:
      case ShapeKind.triangle:
      case ShapeKind.diamond:
      case ShapeKind.pentagon:
      case ShapeKind.hexagon:
      case ShapeKind.star:
        out.add(PathPrimitive(
```

Insert the seven new cases into that fall-through group (between `star` and the `out.add`):

```dart
      case ShapeKind.ellipse:
      case ShapeKind.triangle:
      case ShapeKind.diamond:
      case ShapeKind.pentagon:
      case ShapeKind.hexagon:
      case ShapeKind.star:
      case ShapeKind.arrowRight:
      case ShapeKind.arrowLeft:
      case ShapeKind.arrowUp:
      case ShapeKind.arrowDown:
      case ShapeKind.arrowDouble:
      case ShapeKind.chevron:
      case ShapeKind.roundRect:
        out.add(PathPrimitive(
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/rendering/elements/shape_element_renderer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/rendering/elements/renderers/shape_element_renderer.dart packages/jet_print/test/rendering/elements/shape_element_renderer_test.dart
git commit -m "feat(shape): route arrow + roundRect forms to PathPrimitive"
```

---

## Task 5: l10n strings + gallery roster + label switch

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations.dart` (abstract getters, near line 1182)
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations_en.dart` (near line 560)
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations_tr.dart` (near line 561)
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations_de.dart` (near line 562)
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (`_shapeFormLabel` switch line 3307; `_galleryForms` list line 3325)
- Test: `packages/jet_print/test/domain/elements/shape_element_test.dart` (a lightweight roster test — keeps the deliverable independently testable without spinning up a widget)

**Interfaces:**
- Consumes: the seven new `ShapeKind` values (Task 1).
- Produces: `JetPrintLocalizations.shapeFormArrowRight/ArrowLeft/ArrowUp/ArrowDown/ArrowDouble/Chevron/RoundRect` getters; `_galleryForms` includes the seven; `_shapeFormLabel` maps them.

- [ ] **Step 1: Write the failing test**

Add to `test/domain/elements/shape_element_test.dart` inside `main()`:

```dart
  test('every ShapeKind except line is offered in the gallery roster', () {
    // Mirror of _galleryForms (private) — the roster must list every form a
    // user can author. line is intentionally excluded (not an authoring form).
    const Set<ShapeKind> expectedRoster = <ShapeKind>{
      ShapeKind.rectangle,
      ShapeKind.ellipse,
      ShapeKind.triangle,
      ShapeKind.diamond,
      ShapeKind.pentagon,
      ShapeKind.hexagon,
      ShapeKind.star,
      ShapeKind.arrowRight,
      ShapeKind.arrowLeft,
      ShapeKind.arrowUp,
      ShapeKind.arrowDown,
      ShapeKind.arrowDouble,
      ShapeKind.chevron,
      ShapeKind.roundRect,
    };
    expect(expectedRoster, ShapeKind.values.toSet()..remove(ShapeKind.line));
  });
```

This fails first only conceptually (it actually passes once Task 1 ran). Its real value is the COMPILE gate below + guarding future drift. To get a true red→green for THIS task, the gating failure is the package not compiling until the l10n getters and `_shapeFormLabel` cases exist (the switch must be exhaustive). Proceed to Step 2.

- [ ] **Step 2: Run the analyzer to verify the package does NOT compile**

Run: `cd packages/jet_print && dart analyze lib/src/designer/layout/panels/properties_panel.dart`
Expected: FAIL — `_shapeFormLabel`'s `switch (kind)` is non-exhaustive (missing the seven new `ShapeKind` cases).

- [ ] **Step 3: Add abstract getters**

In `lib/src/designer/l10n/jet_print_localizations.dart`, after the `shapeFormStar` abstract getter (line ~1182), add:

```dart

  /// Shape gallery thumbnail name: a right-pointing block arrow.
  String get shapeFormArrowRight;

  /// Shape gallery thumbnail name: a left-pointing block arrow.
  String get shapeFormArrowLeft;

  /// Shape gallery thumbnail name: an up-pointing block arrow.
  String get shapeFormArrowUp;

  /// Shape gallery thumbnail name: a down-pointing block arrow.
  String get shapeFormArrowDown;

  /// Shape gallery thumbnail name: a two-headed horizontal block arrow.
  String get shapeFormArrowDouble;

  /// Shape gallery thumbnail name: a right-pointing chevron band.
  String get shapeFormChevron;

  /// Shape gallery thumbnail name: a rectangle with rounded corners.
  String get shapeFormRoundRect;
```

- [ ] **Step 4: Add the en implementations**

In `lib/src/designer/l10n/jet_print_localizations_en.dart`, after `String get shapeFormStar => 'Star';` (line ~560):

```dart
  @override
  String get shapeFormArrowRight => 'Arrow right';

  @override
  String get shapeFormArrowLeft => 'Arrow left';

  @override
  String get shapeFormArrowUp => 'Arrow up';

  @override
  String get shapeFormArrowDown => 'Arrow down';

  @override
  String get shapeFormArrowDouble => 'Double arrow';

  @override
  String get shapeFormChevron => 'Chevron';

  @override
  String get shapeFormRoundRect => 'Rounded rectangle';
```

(Match the existing file's `@override` placement style — if the existing getters in this file do not carry an explicit `@override`, omit it to match. Check the lines around `shapeFormStar` and follow that exact style.)

- [ ] **Step 5: Add the tr implementations**

In `lib/src/designer/l10n/jet_print_localizations_tr.dart`, after `String get shapeFormStar => 'Yıldız';` (line ~561):

```dart
  @override
  String get shapeFormArrowRight => 'Sağ ok';

  @override
  String get shapeFormArrowLeft => 'Sol ok';

  @override
  String get shapeFormArrowUp => 'Yukarı ok';

  @override
  String get shapeFormArrowDown => 'Aşağı ok';

  @override
  String get shapeFormArrowDouble => 'Çift ok';

  @override
  String get shapeFormChevron => 'Şerit ok';

  @override
  String get shapeFormRoundRect => 'Yuvarlatılmış dikdörtgen';
```

(Again match the file's existing `@override` style around `shapeFormStar`.)

- [ ] **Step 6: Add the de implementations**

In `lib/src/designer/l10n/jet_print_localizations_de.dart`, after `String get shapeFormStar => 'Stern';` (line ~562):

```dart
  @override
  String get shapeFormArrowRight => 'Pfeil rechts';

  @override
  String get shapeFormArrowLeft => 'Pfeil links';

  @override
  String get shapeFormArrowUp => 'Pfeil hoch';

  @override
  String get shapeFormArrowDown => 'Pfeil runter';

  @override
  String get shapeFormArrowDouble => 'Doppelpfeil';

  @override
  String get shapeFormChevron => 'Winkel';

  @override
  String get shapeFormRoundRect => 'Abgerundetes Rechteck';
```

(Match the file's existing `@override` style.)

- [ ] **Step 7: Extend `_shapeFormLabel` and `_galleryForms`**

In `lib/src/designer/layout/panels/properties_panel.dart`, change `_shapeFormLabel`'s switch (line 3307) — add the seven cases after `ShapeKind.star => l10n.shapeFormStar,`:

```dart
      ShapeKind.star => l10n.shapeFormStar,
      ShapeKind.arrowRight => l10n.shapeFormArrowRight,
      ShapeKind.arrowLeft => l10n.shapeFormArrowLeft,
      ShapeKind.arrowUp => l10n.shapeFormArrowUp,
      ShapeKind.arrowDown => l10n.shapeFormArrowDown,
      ShapeKind.arrowDouble => l10n.shapeFormArrowDouble,
      ShapeKind.chevron => l10n.shapeFormChevron,
      ShapeKind.roundRect => l10n.shapeFormRoundRect,
```

And append the seven to `_galleryForms` (line 3325), after `ShapeKind.star,`:

```dart
  ShapeKind.star,
  ShapeKind.arrowRight,
  ShapeKind.arrowLeft,
  ShapeKind.arrowUp,
  ShapeKind.arrowDown,
  ShapeKind.arrowDouble,
  ShapeKind.chevron,
  ShapeKind.roundRect,
```

- [ ] **Step 8: Run the analyzer + roster test to verify green**

Run: `cd packages/jet_print && dart analyze lib/src/designer && flutter test test/domain/elements/shape_element_test.dart`
Expected: "No issues found!" and PASS.

- [ ] **Step 9: Commit**

```bash
git add packages/jet_print/lib/src/designer/l10n packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/domain/elements/shape_element_test.dart
git commit -m "feat(shape): gallery roster + l10n for arrow + roundRect forms"
```

---

## Task 6: Codec forward-compat coverage for the new forms

**Files:**
- Test only: `packages/jet_print/test/domain/serialization/shape_element_codec_test.dart`

**Interfaces:**
- Consumes: the seven new `ShapeKind` values; the existing `ShapeElementCodec` (no source change — the codec already serializes by `name` and the C8.1 loop iterates `ShapeKind.values`, so the new forms are already exercised; this task adds an explicit anchor + the still-unknown-name degrade check).

- [ ] **Step 1: Write the test**

Add inside `main()` in `test/domain/serialization/shape_element_codec_test.dart`:

```dart
  group('new forms round-trip + unknown-name still degrades (block arrows)', () {
    test('roundRect serializes by name and decodes back equal', () {
      const ShapeElement s = ShapeElement(
        id: 's',
        bounds: JetRect(x: 4, y: 6, width: 50, height: 30),
        kind: ShapeKind.roundRect,
        style: JetBoxStyle(stroke: JetColor.black, strokeWidth: 2),
      );
      final Map<String, Object?> json = codec.toJson(s);
      expect(json['kind'], 'roundRect');
      expect(codec.fromJson(json), s);
    });

    test('an unknown future form name still loads as rectangle, name preserved', () {
      final Map<String, Object?> json = codec.toJson(const ShapeElement(
        id: 's',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        kind: ShapeKind.rectangle,
      ));
      json['kind'] = 'someFutureArrow';
      final ShapeElement decoded = codec.fromJson(json);
      expect(decoded.kind, ShapeKind.rectangle);
      expect(decoded.unknownForm, 'someFutureArrow');
      expect(codec.toJson(decoded)['kind'], 'someFutureArrow');
    });
  });
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/domain/serialization/shape_element_codec_test.dart`
Expected: PASS (the codec already handles this — this task pins the contract for the new forms).

- [ ] **Step 3: Commit**

```bash
git add packages/jet_print/test/domain/serialization/shape_element_codec_test.dart
git commit -m "test(shape): codec round-trip + forward-compat for new forms"
```

---

## Task 7: Golden — new forms render WYSIWYG

**Files:**
- Modify: `packages/jet_print/test/designer/goldens/shape_forms_test.dart` (widen the page, add the new forms to the row)
- Golden assets: regenerated under the test's golden directory.

**Interfaces:**
- Consumes: all prior tasks (forms must render).
- Produces: a golden proving the new forms render identically on canvas and export. Existing-form goldens for ellipse…star are unchanged (this test's page is extended, so its OWN golden is regenerated; the separate line/rectangle report goldens elsewhere are untouched → byte-identical).

- [ ] **Step 1: Extend the form row**

In `test/designer/goldens/shape_forms_test.dart`, widen `_page` and add the new forms. Replace the `_page` width and the `_definition()` element list. Change:

```dart
const PageFormat _page = PageFormat(
  width: 452,
  height: 96,
  margins: JetEdgeInsets.all(8),
);
```

to (13 forms × 72px stride + 8px margins ≈ 952):

```dart
const PageFormat _page = PageFormat(
  width: 952,
  height: 96,
  margins: JetEdgeInsets.all(8),
);
```

and replace the `elements:` list in `_definition()`:

```dart
              elements: <ReportElement>[
                _form('ellipse', ShapeKind.ellipse, 0),
                _form('triangle', ShapeKind.triangle, 72),
                _form('diamond', ShapeKind.diamond, 144),
                _form('pentagon', ShapeKind.pentagon, 216),
                _form('hexagon', ShapeKind.hexagon, 288),
                _form('star', ShapeKind.star, 360),
                _form('arrowRight', ShapeKind.arrowRight, 432),
                _form('arrowLeft', ShapeKind.arrowLeft, 504),
                _form('arrowUp', ShapeKind.arrowUp, 576),
                _form('arrowDown', ShapeKind.arrowDown, 648),
                _form('arrowDouble', ShapeKind.arrowDouble, 720),
                _form('chevron', ShapeKind.chevron, 792),
                _form('roundRect', ShapeKind.roundRect, 864),
              ],
```

- [ ] **Step 2: Regenerate the golden for THIS test**

Run: `cd packages/jet_print && flutter test --update-goldens test/designer/goldens/shape_forms_test.dart`
Expected: PASS, golden file(s) for this test updated.

- [ ] **Step 3: Verify the golden now matches (no `--update-goldens`)**

Run: `cd packages/jet_print && flutter test test/designer/goldens/shape_forms_test.dart`
Expected: PASS.

- [ ] **Step 4: Confirm NO other golden changed (byte-identical guarantee)**

Run: `git status --porcelain packages/jet_print/test`
Expected: only `shape_forms_test.dart` and ITS golden asset(s) appear as modified/new — no other `.png` golden touched.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/test/designer/goldens/shape_forms_test.dart
git add packages/jet_print/test/designer/goldens/  # the regenerated golden asset(s) for this test
git commit -m "test(shape): WYSIWYG golden for arrow + roundRect forms"
```

---

## Task 8: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the whole package test suite**

Run: `cd packages/jet_print && flutter test`
Expected: all tests PASS, 0 failures. Note the new total vs the prior baseline (it should rise by the number of new tests added in Tasks 1-7).

- [ ] **Step 2: Analyze the whole package**

Run: `cd packages/jet_print && dart analyze`
Expected: "No issues found!"

- [ ] **Step 3: Confirm existing goldens byte-identical**

Run: `git status --porcelain` from repo root.
Expected: no unexpected golden `.png` changes beyond the single `shape_forms_test` asset from Task 7.

- [ ] **Step 4 (manual, optional but recommended): GUI smoke**

Launch the playground, select a shape element, open the shape gallery in Properties, and confirm the seven new thumbnails appear and render correctly when picked; confirm export/preview match the canvas. This is a human check — no automated step.

---

## Self-Review Notes

- **Spec coverage:** enum (T1), arrow geometry (T2), roundRect geometry (T3), renderer routing (T4), gallery + l10n (T5), codec forward-compat (T6), golden (T7), full verify (T8). All seven forms + all five touched components covered.
- **Vertex counts pinned:** arrows 7, double 10, chevron 6, roundRect `4·(kCornerSegments+1)`=36 — consistent between T2/T3 geometry and their tests.
- **Type/name consistency:** getter names `shapeFormArrowRight`…`shapeFormRoundRect` identical across abstract base, en/tr/de impls, and the `_shapeFormLabel` switch.
- **Byte-identical guarantee:** only `shape_forms_test`'s own golden regenerates (T7 step 4 + T8 step 3 verify nothing else moves).
