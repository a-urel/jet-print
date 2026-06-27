# Block Arrow & Rounded-Rectangle Shapes — Design

**Date:** 2026-06-27
**Status:** Approved (pending spec review)
**Type:** Additive feature (new closed shape forms)

## Summary

Add seven new forms to `ShapeKind` — six block arrows and a rounded
rectangle — drawn as closed inscribed polygons through the existing
single-geometry-source (`shapePath`). Purely additive: no new render
machinery, no codec change, no change to existing forms or their goldens,
and old reports load byte-identical.

New forms:

| Value         | Form                                          |
|---------------|-----------------------------------------------|
| `arrowRight`  | Horizontal block arrow pointing right         |
| `arrowLeft`   | Horizontal block arrow pointing left          |
| `arrowUp`     | Vertical block arrow pointing up              |
| `arrowDown`   | Vertical block arrow pointing down            |
| `arrowDouble` | Two-headed horizontal block arrow             |
| `chevron`     | Right-pointing ">"-band (tail-less arrowhead) |
| `roundRect`   | Rectangle with rounded corners                |

## Why this fits the architecture

`shapePath(kind, bounds)` is the one definition of a form's vertices,
consumed by both the renderer (`PathPrimitive`) and the designer gallery
thumbnail, so the picker icon cannot drift from the printed result. Forms
serialize by enum `name`; the codec already round-trips unknown form names
losslessly (`ShapeElement.unknownForm`). Adding enum values is therefore
additive in every direction:

- old reports (no arrows) load byte-for-byte unchanged
- reports authored with arrows degrade gracefully on older builds
  (rendered as rectangle, original name preserved on re-save)

`line` and `rectangle` keep their special-cased primitives; all six arrows
join the existing closed-form group (`ellipse`/`triangle`/.../`star`).

## Geometry

All arrows **stretch with bounds** (ratios relative to width/height) — the
same behaviour every existing closed form has (ellipse, star). No new
resize logic.

Ratio tunables live beside `kEllipseSegments` in `shape_path.dart`:

```
kArrowShaftRatio       = 0.50  // shaft thickness ÷ cross-axis
kArrowHeadRatio        = 0.45  // head length     ÷ long-axis
kChevronThicknessRatio = 0.50  // band thickness  ÷ long-axis
kRoundRectRadiusRatio  = 0.20  // corner radius   ÷ min(w, h)
kCornerSegments        = 8     // LineTo steps per rounded corner
```

### Single arrow — 7-vertex polygon (right-pointing reference)

Let the box span `x..x+w`, `y..y+h`; `cy = y + h/2`;
`shaftHalf = kArrowShaftRatio/2 · h`; `headW = kArrowHeadRatio · w`.

```
1. (x,          cy - shaftHalf)   shaft top-left
2. (x+w-headW,  cy - shaftHalf)   head base, top inner
3. (x+w-headW,  y)                head top outer
4. (x+w,        cy)               tip
5. (x+w-headW,  y+h)              head bottom outer
6. (x+w-headW,  cy + shaftHalf)   head base, bottom inner
7. (x,          cy + shaftHalf)   shaft bottom-left
```

`arrowLeft` mirrors X about the box centre; `arrowUp`/`arrowDown` swap the
roles of width/height (vertical shaft, head at top/bottom). Each is its own
vertex list — explicit, not a runtime rotation — to keep `shapePath` a flat
`switch` like the existing forms.

### Double arrow — 8-vertex polygon (heads at both ends)

`headW = kArrowHeadRatio · w` at each end; central shaft band of thickness
`kArrowShaftRatio · h`; tips at `(x, cy)` and `(x+w, cy)`.

### Chevron — 6-vertex ">"-band (right-pointing)

Let `t = kChevronThicknessRatio · w`.

```
1. (x,        y)          outer top-left
2. (x+w,      cy)         tip
3. (x,        y+h)        outer bottom-left
4. (x+t,      y+h)? 
```

(Exact chevron vertices finalized in the plan; conceptually: outer ">"
edge from top-left to tip to bottom-left, inner edge offset by `t` toward
the tip, forming a constant-thickness band with a left-facing notch.)

### Rounded rectangle — corner-fan polygon

A true rounded corner is a quarter-circle arc, but `PathCommand` has no
curve command — the engine already approximates curves with line segments
(the ellipse 64-gon, chosen "so no curve primitive and no new painter code
is needed"). `roundRect` reuses that pattern: each of the four corners is a
fan of `kCornerSegments` `LineTo` steps along a quarter-circle of radius
`r = kRoundRectRadiusRatio · min(w, h)` (clamped so `r ≤ min(w,h)/2`,
keeping a degenerate box safe). The path is the four straight edges joined
by the four corner fans, closed. Faceted rather than mathematically crisp —
the same tradeoff already accepted for ellipse — in exchange for zero
painter change and automatic canvas/preview/export parity. The sharp
`rectangle` keeps its dedicated `RectPrimitive`; `roundRect` is a distinct
`PathPrimitive` form.

## Components touched

Mechanical, mirrors the existing six closed forms exactly:

1. **`domain/elements/shape_element.dart`** — seven `ShapeKind` values + doc
   comments. No other change to `ShapeElement` (copyWith/codec/== all key
   off `kind` generically).
2. **`rendering/elements/shape_path.dart`** — the ratio/segment constants + a
   vertex list per new form in the `switch` (`roundRect` builds its four
   corner fans).
3. **`rendering/elements/renderers/shape_element_renderer.dart`** — add the
   seven values to the existing closed-form `case` group (they fall through
   to the shared `PathPrimitive` + `shapePath` branch).
4. **`designer/layout/panels/properties_panel.dart`** — append the seven to
   `_galleryForms` (roster order).
5. **l10n** (`jet_print_localizations*.dart`) — `shapeForm<X>` name strings
   for en/tr/de + getters, following the existing `shapeFormStar` pattern.

## Out of scope (YAGNI)

- Line arrows / connectors (a line + arrowhead) — different render path,
  explicitly deferred.
- Adjustable per-element head/shaft handles — global tunables only.
- Fixed-aspect resize — arrows stretch like every other form.

## Testing

- `shape_path_test.dart` — vertex/closure assertions per new form
  (count, first vertex, tip position, closed path). For `roundRect`:
  vertex count = `4 · kCornerSegments` (+1 per corner join as built),
  radius clamp on a degenerate box, all vertices inside bounds.
- `shape_element_codec_test.dart` — round-trip each new `name`; confirm an
  unknown future name still degrades to rectangle.
- `shape_forms_test.dart` (golden) — regenerate to include the six new
  thumbnails. Existing-form goldens unchanged.
- `shape_element_renderer_test.dart` — each new form emits a `PathPrimitive`
  (not Rect/Line).
- A balanced default smoke: `arrowRight` in a wide box renders a long flat
  arrow; tall box renders a short fat one (stretch confirmation).

## Acceptance

- All existing tests green, all existing goldens byte-identical.
- Seven new forms selectable in the gallery, render identically on
  canvas / preview / export.
- A pre-arrow report loads and re-saves byte-identical.
