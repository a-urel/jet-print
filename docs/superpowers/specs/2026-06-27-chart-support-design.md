# Chart Support — Design

**Date:** 2026-06-27
**Status:** Approved (brainstorm) — ready for implementation plan
**Scope:** Add bar / line / pie charts to jet-print as a first-class report element.

## Goal

Let report authors place a chart on a band, bind it to a collection field in
scope, and have it render identically across the Flutter canvas, PDF, and PNG
back-ends (WYSIWYG, Constitution IV). v1 covers vertical bar, line, and pie,
single series, sourced from one bound collection.

## Constraints That Shape Everything

1. **Flutter-free render seam.** The engine emits its own frame primitives once
   (rects, paths, text runs), then renders them three ways: Flutter canvas, PDF
   (pure Dart — no Flutter), PNG. Goldens assert fidelity across all three.
   → A widget-based chart library (fl_chart, syncfusion, charts_flutter) only
   paints to a Flutter `Canvas`, cannot traverse the pure-Dart PDF path, and
   cannot be golden-tested. **Ruled out. No third-party chart dependency. No
   widget.** Charts are drawn as frame primitives from an in-house pure-Dart
   geometry layer — the exact pattern `barcode/` already uses (a pure-Dart lib
   computes bars, the renderer emits rects).

2. **Resolved-element seam.** Renderers never evaluate expressions. The fill
   phase (`ElementResolver.resolve`) produces a *resolved* copy of each element
   with all data-bearing fields reduced to literals; the renderer just draws it
   (the text renderer draws `el.text`, already resolved). → A chart's bound
   collection + category/value expressions are evaluated at fill time into a
   concrete series; the renderer receives geometry-ready data only.

3. **One element type, enum-discriminated.** Mirrors `ShapeElement` +
   `ShapeKind`: one `ChartElement` carries a `ChartType { bar, line, pie }`.
   Additive new types later, serialize-by-name, no schema-version bump. Chosen
   over separate per-type element classes.

## Non-Goals (v1 YAGNI boundary)

Deferred — not in this slice: stacked / grouped bar, area, scatter, donut hole,
multi-series, per-point colors, manual axis min/max, axis number formatting,
label rotation, static/inline (non-bound) data, legends beyond a simple
single-series swatch, interactivity/animation (cannot survive PDF anyway).

## Architecture

Five layers, each a thin slice, dependencies pointing inward (Constitution II).

### 1. Domain — `ChartElement`

New `lib/src/domain/elements/chart_element.dart`, a `ReportElement` subtype.

Fields:
- `chartType` — `ChartType { bar, line, pie }`.
- `collectionField` — name of the bound collection field, resolved in the
  element's band scope (the list the chart iterates).
- `categoryExpression` — per-item label expression (e.g. `$F{month}`). May be
  null for pie (slice label defaults to index) — decide in plan.
- `valueExpression` — per-item numeric value expression (e.g. `$F{revenue}`).
- `title` — optional `String?` chart title.
- chrome flags: `showAxes` / `showValueLabels` / `showLegend` (bool, sensible
  defaults so a default chart looks complete).
- `seriesColor` — `JetColor` for bars/line; pie derives a palette (deterministic
  per slice index) — palette source decided in plan.
- `typeKey => 'chart'`.
- implements `withBounds`, `withName`, `withVisible` (preserve every other
  field — see Risks).

A small `ChartType` enum lives beside the element (like `ShapeKind`). Serialize
by name.

### 2. Serialization — `ChartElementCodec`

New `lib/src/domain/serialization/chart_element_codec.dart`. Omit-when-default
encoding (every recent codec does this). Registered as the `'chart'` pair in
`registerBuiltInElementTypes` (`built_in_element_renderers.dart`) alongside
text/shape/image/barcode. Round-trips through an `UnknownElement` untouched when
a consumer hasn't registered it (existing contract). No schema-version bump.

### 3. Fill — resolved series

`ElementResolver.resolve` gains a `ChartElement` branch → `_resolveChart`:

1. Read the bound collection off the render row: `row.field(collectionField)`
   returns the raw nested value.
2. Coerce raw → `List<DataRow>`. The coercion already exists inline in
   `report_filler.dart` `childRowsOf` (lib/src/rendering/fill/report_filler.dart
   ~L284-303). **Extract it to a shared pure helper** (e.g.
   `data/collection_rows.dart` `coerceCollectionRows(Object? raw, …)`) so the
   filler and the chart resolver agree on coercion (list-of-maps → rows). The
   filler is refactored to call the shared helper (behavior-preserving; goldens
   unchanged).
3. Per item, evaluate `categoryExpression` + `valueExpression` against the child
   row (reusing `FillEvalContext` / the function registry, as text resolution
   does) → `(label: String, value: double)`.
4. Return a resolved `ChartElement` carrying a concrete
   `List<ChartPoint>` series. Expressions are gone; the resolved element is
   geometry-ready and self-contained.

Diagnostics: non-numeric value, missing field, empty collection — surfaced
through the existing `ReportDiagnostics` sink with per-row dedup
(`warnedFields`), matching text/image resolution. Empty collection → renderer
draws an empty-state placeholder (decide: blank box vs "no data" — plan).

**Placement** is governed entirely by existing scope rules. The chart needs
`collectionField` resolvable in its band, which is exactly what
`binding_resolution.dart` / `collectionFieldsForScope` already determine. A
chart in an order-detail band bound to `lines` renders one chart per order; a
chart in a summary band bound to a top-level collection renders once. No new
placement machinery; the designer's false-warning resolution already handles
collection refs.

### 4. Render — pure-Dart geometry → frame primitives

New directory `lib/src/rendering/elements/chart/` (parallels `barcode/`):

- `chart_geometry.dart` — **pure Dart, no Flutter, no chart lib.** Input:
  resolved series + target box. Output: positioned primitives:
  - bar: one rect per point, scaled to a nice-number Y axis.
  - line: a polyline path across points, scaled to the Y axis.
  - pie: arc/wedge paths summing to 360°, slice angles from value share.
  - axis: nice-number tick selection (the classic "nice numbers" algorithm),
    tick positions, gridline Y coordinates, category X label anchors.
  - labels: value/category/percent label positions + alignment.
- `chart_element_renderer.dart` — `ElementRenderer<ChartElement>`. `measure`
  returns the element's box (charts fill their bounds). `emit` calls
  `chart_geometry`, then appends the computed primitives to the `FrameBuilder`
  using the **existing primitive vocabulary** (rects, paths via the same seam
  `shape`/`barcode` use, text runs via the measurer). No new frame-primitive
  types. Registered in `registerBuiltInElementTypes`.

Chrome rendered in v1: Y axis with ticks + gridlines and X category labels
(bar/line); slice value/percent labels (pie); optional title; simple
single-series legend swatch.

### 5. Designer

- **Element-type registry + canvas thumbnail.** A new visual type touches
  **three** switches, including the thumbnail painter — the `ShapeKind` lesson
  (a prior shape slice missed `_ShapeThumbPainter.paint`). The plan must
  enumerate all three.
- **Properties panel:** chart-type picker (bar/line/pie), collection-field
  picker (in-scope collections via `collectionFieldsForScope`), category- and
  value-expression fields (fx editor), title field, axis/value-label/legend
  toggles, series color.
- **Commands** for each edit (undo/redo), one per mutation. Each command
  rebuilds the element preserving **all** other fields.

### Data flow

```
authored ChartElement (collectionField + exprs)
  → ElementResolver._resolveChart  (read row collection → coerce rows →
                                     eval category/value per item)
  → resolved ChartElement (concrete List<ChartPoint>)
  → ChartElementRenderer.emit → chart_geometry → frame primitives
  → {Flutter canvas | PDF | PNG}  (identical)
```

## Testing Strategy

- **Geometry (unit, pure, fast):** nice-number axis selection; bar rect math;
  pie angle sums to 360°; line point mapping; label anchoring. No I/O.
- **Resolver (unit):** bound collection → series; category/value eval; empty
  collection; non-numeric value diagnostic; missing-field diagnostic.
- **Codec (unit):** round-trip every field; omit-when-default; unknown-type
  passthrough.
- **Golden (fidelity):** one report per chart type (bar, line, pie) rendered to
  canvas + PDF + PNG; assert all match. These are the WYSIWYG proof.
- **Designer (widget):** canvas thumbnail renders; properties panel edits each
  field; collection-field picker lists in-scope collections; no false
  "field not found" warning for a valid collection ref.

## Risks & Mitigations

1. **Silent field-drop in copy-constructors / commands** — the recurring trap.
   Every recent element feature (rename, visible, field-description) lost a
   field in some rebuilder, caught only by review. *Mitigation:* the plan
   enumerates every `ChartElement`-rebuilding site (withBounds/withName/
   withVisible, codec, each command) and a round-trip test asserts no field is
   dropped.
2. **New visual type = three switches** (ShapeKind lesson). *Mitigation:* plan
   lists all three explicitly, including the designer thumbnail painter.
3. **Collection coercion divergence** — chart resolver and filler must coerce
   the raw nested value identically. *Mitigation:* extract one shared helper;
   filler refactored to use it (behavior-preserving, goldens unchanged).
4. **Goldens are the contract** — any unexpected golden change during the
   filler refactor (step 3) means a behavior change; STOP and inspect.
5. **Hand-drawn geometry is basic** (no gradients/anti-alias flourish a widget
   lib gives). Accepted: correct for static vector print/PDF output;
   deterministic and golden-testable.

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — `ChartElement` public; geometry pure under `src/`. |
| II. Layered architecture | PASS — domain → data(coerce/resolve) → render geometry → designer; deps inward; render seam stays Flutter-free. |
| III. Test-First | PASS — geometry/resolver/codec Red→Green; goldens gate fidelity. |
| IV. Rendering fidelity / WYSIWYG | PASS — single frame-primitive emission, three back-ends, golden-asserted. |
| V. Serialization | PASS — additive codec, serialize-by-name, omit-when-default, no schema bump, unknown-type passthrough. |
| VI. Docs/DX | PASS — dartdoc on public element + geometry; analyzer + `dart format` gate. |

No violations → Complexity Tracking omitted.
