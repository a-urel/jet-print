# Phase 0 Research: Shape Gallery in Properties Pane

All unknowns from the Technical Context are resolved below. Each decision is grounded in the existing
codebase seams discovered during exploration.

## D1 — How new shape forms reach the page: reuse `PathPrimitive`, add no painter code

- **Decision**: Render every non-line/-rectangle form by emitting a single
  [`PathPrimitive`](../../packages/jet_print/lib/src/rendering/frame/primitive.dart#L183) whose
  `commands` come from a new `shapePath(ShapeKind, JetRect)`. Keep rectangle → `RectPrimitive` and
  line → `LinePrimitive` exactly as they are today.
- **Rationale**: `PathPrimitive` and its `MoveTo`/`LineTo`/`ClosePath` commands are **already** painted
  identically by `CanvasPainter.drawPath` and `PdfPainter.drawPath`, and dispatched by the exhaustive
  `paintFrame` switch. So new forms inherit canvas/preview/PDF/PNG fidelity (Constitution IV) without a
  single new line of painter code and without forking any render path. The renderer's `switch (el.kind)`
  is exhaustive with no `default`, so each unhandled new enum value is a **compile-time** failure —
  Test-First enforced by the type system.
- **Alternatives considered**:
  - *A custom `CustomPainter` per shape in the designer* — rejected: it would create a designer-only
    drawing path divergent from export, the exact WYSIWYG violation the constitution forbids.
  - *A new primitive type per shape (TrianglePrimitive, …)* — rejected: needless surface; every painter
    and the exhaustive dispatch would grow per form. Polygons are fully expressible as paths.

## D2 — The ellipse: a high-segment polygon, not a new curve primitive

- **Decision**: Render the ellipse as a **64-segment** polygon inscribed in the bounds, built from
  `LineTo` commands by `shapePath`. Segment count is a single named constant.
- **Rationale**: The `PathCommand` set has no curve (`CubicTo`/arc). Adding one would expand the sealed
  command type and force new code in *every* painter plus golden churn — surface unjustified by this
  feature. A 64-gon is visually smooth at report point sizes and at typical export DPI, and reuses the
  existing `LineTo` replay, so canvas == preview == PDF holds by construction. 64 balances smoothness
  against primitive size; it is trivially tunable if a fidelity issue is ever observed.
- **Alternatives considered**:
  - *Add a `CubicTo` path command + a 4-bézier ellipse* — rejected for surface/golden cost; revisit
    only if polygonal smoothness proves insufficient.
  - *A dedicated `OvalPrimitive`* — rejected: same per-primitive painter cost as D1's rejected option.

## D3 — The form roster and their geometry (inscribed in bounds)

- **Decision**: `shapePath` produces, all inscribed in `JetRect bounds` so the form changes but never
  the position/size (FR-011):
  - **line / rectangle** — handled by the renderer's existing special cases (not by `shapePath`).
  - **ellipse** — 64-gon on the bounds' inscribed ellipse.
  - **triangle** — apex at top-center, base across the bottom edge.
  - **diamond** — the four edge midpoints.
  - **pentagon / hexagon** — regular, equilateral, inscribed in the bounds (vertices on the bounds'
    inscribed circle/ellipse), pentagon point-up.
  - **star** — 5-point, point-up, conventional inner/outer radius ratio (0.5 outer→inner) — a fixed
    design-time default, not user-configurable (per spec Assumptions).
- **Rationale**: These match the spec's named roster and "equilateral, inscribed" assumption. Anchoring
  every vertex to `bounds` guarantees form-only change. Non-square bounds simply scale the inscribed
  circle to an ellipse — acceptable and expected (the bounds box is the authoring control).
- **Edge handling**: `shapePath` must not throw on a 1×1 or 1×N degenerate box; it returns a (possibly
  tiny/collapsed) closed path. The renderer still emits a `PathPrimitive`; painting a zero-area path is
  a no-op, never an error (spec edge case).

## D4 — Lossless unknown-form round-trip: an optional `unknownForm` field

- **Decision**: Add `String? unknownForm` to `ShapeElement`. The codec's `fromJson` attempts
  `ShapeKind.values.byName(name)`; on failure it sets `kind = ShapeKind.rectangle` (safe render
  default) and `unknownForm = name`. `toJson` writes `unknownForm` back as the `kind` string when it is
  non-null; otherwise it writes `kind.name`. An explicit gallery pick clears `unknownForm`.
- **Rationale**: This satisfies FR-009 exactly — "render as rectangle but keep the original form name so
  re-saving does not lose it" — with a minimal additive field, **no schema-version bump, no migration**.
  Known forms remain wire-identical (`kind: <enum name>`), so pre-feature reports load byte-for-byte
  unchanged (Constitution V). The field is the single source of the preserved string; once the user
  deliberately re-picks a known form, the unknown is intentionally replaced.
- **Alternatives considered**:
  - *Type the form as a free `String` instead of an enum* — rejected: loses exhaustiveness (the
    compile-time safety net of D1) and touches every existing `kind` use-site.
  - *Throw / drop unknown forms on load* — rejected: violates FR-009 and Constitution V (lossy).
  - *A schema migration* — rejected: nothing about the existing format changes; a migration would be
    ceremony with no payload.

## D5 — One undoable controller op, no-op-safe, line-coherent

- **Decision**: `JetReportDesignerController.setShapeKind(String id, ShapeKind kind)` commits a private
  `SetShapeKindCommand` through the existing `_commit` path. The command: preserves `bounds`/`style`;
  sets `flipDiagonal = false` when the new `kind != line` (keeps it when staying on/returning to line);
  clears `unknownForm`; and returns `before` unchanged when the element already has that `kind` (and no
  unknownForm to clear), so `_commit` records no history and fires no notification.
- **Rationale**: Mirrors `setGeometry`/`setPageFormat`: the designer composes the desired value and the
  controller routes one immutable change through history, giving exactly one undo step (FR-006) and a
  free no-op guard (FR-005). Resetting `flipDiagonal` off line keeps the line-only option coherent
  (spec edge case); clearing `unknownForm` ensures a deliberate pick fully replaces a preserved unknown.
- **Alternatives considered**:
  - *Granular setters (`setShapeForm`, `setFlipDiagonal` invoked together)* — rejected: a form change is
    one conceptual edit; two ops would risk two undo steps.

## D6 — The gallery thumbnails reuse the renderer geometry

- **Decision**: Each gallery thumbnail is a small `CustomPaint` that draws the form via the **same**
  `shapePath(kind, thumbBounds)`, stroked/filled with a neutral chrome style. The active form is
  highlighted; each item is a `Semantics(button, label: <localized form name>)`, keyboard reachable.
- **Rationale**: Sharing `shapePath` means the picker icon is literally the rendered shape's geometry —
  the gallery cannot drift from the canvas result, reinforcing IV at the UI layer. Reuses the panel's
  established `Semantics`/focus conventions (FR-012). Names are localized so the picker is operable
  without sight of the glyph (SC-006 is visual; the accessible name is the non-visual equivalent).
- **Alternatives considered**:
  - *Static icon assets per shape* — rejected: a second source of truth that can disagree with the
    renderer and adds asset-loading/localization-of-images overhead.

## Resolved unknowns summary

| Unknown | Resolution |
|---------|-----------|
| How do new forms render across canvas/preview/export? | Emit `PathPrimitive` from `shapePath`; reuse existing painters; no forked path (D1). |
| How is the ellipse drawn without a curve primitive? | 64-segment inscribed polygon, tunable constant (D2). |
| What geometry does each of the 8 forms use? | Inscribed-in-bounds table; degenerate-box-safe (D3). |
| How are unrecognized saved forms handled losslessly? | `unknownForm` field: load→rectangle+keep name, save→write name back; schema stays 1 (D4). |
| How is a form change made one undoable, no-op-safe step? | `setShapeKind` → `SetShapeKindCommand` via `_commit`; resets flip off line, clears unknownForm (D5). |
| How does the gallery avoid divergence from the rendered shape? | Thumbnails paint through the same `shapePath` (D6). |
