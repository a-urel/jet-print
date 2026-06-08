# Phase 0 Research: Designer Edit Surface

**Feature**: `003-designer-edit-surface` | **Date**: 2026-06-08
**Input**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md)

This document resolves every open decision the [plan's Technical Context](plan.md#technical-context)
marks as needing research. Each entry is **Decision / Rationale / Alternatives considered**.
The codebase facts these decisions rest on were gathered by reading the domain, rendering,
serialization, and designer seams directly (see file references inline).

---

## D1 — Design-time rendering reuse (Constitution IV gate)

**Decision**: The design canvas renders element appearance by reusing the **existing**
`ElementRenderer.emit()` → `FrameBuilder` → `PageFrame` → `CanvasPainter` pipeline verbatim.
A new, thin **design-time layout** (`design_time_frame.dart`) stacks the template's bands
top-to-bottom in *design order* at their authored `height`, offsets each element's band-local
`bounds` to absolute page coordinates, and calls the unchanged `ElementRenderer.emit()` for each
element into a `FrameBuilder`. The resulting `PageFrame` is painted by the unchanged
`CanvasPainter`. **No element-drawing code is duplicated.**

**Rationale**:
- Constitution IV (NON-NEGOTIABLE) forbids "parallel, divergent rendering code." The *fidelity-
  critical* code is how each element type becomes pixels — that lives entirely in the element
  renderers (`rendering/elements/renderers/*.dart`) and `CanvasPainter`
  (`rendering/paint/canvas_painter.dart`). Both are reused unchanged, so canvas == preview ==
  print for the same element.
- The full `ReportLayouter` (`rendering/layout/report_layouter.dart`) does data-driven
  **pagination**, page-chrome repetition, group handling, and page-scoped expression
  substitution — none of which apply to a design-time, no-data view that shows one continuous
  page of authored bands. Reusing `ReportLayouter` would force a synthetic `FilledReport` and
  fight its pagination. The reusable kernel inside the layouter is its `place()` helper
  (`report_layouter.dart:231-246`): translate band-local boxes to the page and call
  `renderer.emit(...)`. The design-time builder mirrors exactly that two-line kernel — the same
  emit call, a different (simpler, non-paginated) band geometry.
- Band-stacking geometry is legitimately design-specific (a designer shows the layout you author;
  print shows the paginated data run). Sharing *that* would be wrong, not required.

**Alternatives considered**:
- *Render with bespoke Flutter widgets per element type* (a `Text`, a `Container`, an `Image`…):
  rejected — creates a second, divergent rendering path → direct Constitution IV violation, and
  would drift from print output.
- *Drive the full `ReportLayouter` with a synthetic single-page `FilledReport`*: rejected —
  pagination/chrome/group logic is unwanted at design time and would split tall bands across
  pages, contradicting the "continuous design page" model. The shared kernel (`emit`) is reused
  without inheriting the unwanted pagination.

**Asset preparation vs. per-frame paint** (performance constraint): `CanvasPainter.prepare()` is
`async` (it loads fonts via `ui.loadFontFromList` and decodes image bytes). A `CustomPainter.paint`
must be synchronous. Decision: **separate preparation from painting**. The base design-time frame
is rasterized to a cached `ui.Picture`/`ui.Image` once per *committed* model change (after an async
`prepare`); pan, zoom, selection, hover, and live drag re-blit the cached picture under a new
transform and draw lightweight overlays on top — no re-prepare, no re-emit. See D5.

---

## D2 — Public API expansion: model + serialization (Constitution I / V)

**Decision**: This feature **adds the report model and its serialization to the single public
entry point** (`packages/jet_print/lib/jet_print.dart`), reversing the explicit 002 non-goal
("No domain/report-model types … No rendering/serialization API"). The newly exported surface is
the minimum needed to *host, construct, mutate, and round-trip* a design:

- **Model types**: `ReportTemplate`, `ReportBand`, `BandType`, `PageFormat`; the element
  hierarchy `ReportElement`, `TextElement`, `ShapeElement`, `ShapeKind`, `ImageElement`,
  `JetBoxFit`, `JetImageSource` (+ concrete sources), `BarcodeElement`, `BarcodeSymbology`,
  `UnknownElement`; geometry `JetRect`, `JetSize`, `JetOffset`, `JetEdgeInsets`; styles
  `JetTextStyle`, `JetBoxStyle`, `JetColor` (+ enums they expose). Supporting carriers held by
  the template — `ReportParameter`, `ReportVariable`, `ReportGroup` — are exported too so a
  loaded template round-trips losslessly even though this spec does not *edit* them.
- **Serialization facade**: a public `JetReportFormat` wrapping the existing
  `encodeTemplate`/`decodeTemplate` (`domain/serialization/report_codec.dart`) with the built-in
  element codecs pre-registered (`registerBuiltInElementCodecs`) and the schema version /
  migration machinery wired. Methods: `encode(ReportTemplate) → Map<String,Object?>`,
  `decode(Map) → ReportTemplate`, plus JSON-string conveniences `encodeJson`/`decodeJson`. This
  is the "report file format" contract end users own (Constitution V).

**Rationale**:
- Constitution I makes the library the product and every app a consumer "through its public API —
  never through private internals." FR-022 requires a consumer (the tester app) to **open and
  save** via the existing serialization; FR-003 requires an in-memory model the surface mutates.
  Neither is reachable without exposing the model + codec. The 002 deferral was correct *for a
  layout-only iteration*; this iteration's scope retires it.
- It is also the forward bridge to engine spec 009 (export) and the data-binding spec, both of
  which need the model public. Exposing it now, once, avoids a churn of partial exposures.
- Serialization is *already* versioned, migration-aware, and round-trip-tested
  (`test/domain/serialization/*`), so the format is safe to make public per Constitution V.

**Scope guard**: Only types reachable from a `ReportTemplate` are exported. Internal rendering,
expression-engine, fill, and data-source seams stay private. The encapsulation test
(`test/encapsulation_test.dart`) continues to forbid `package:jet_print/src/...` imports.

**Alternatives considered**:
- *Opaque handle* — keep the model private, expose only `controller.loadJson(String)/toJson()`:
  rejected. Consumers could not construct or inspect a report programmatically (needed for the
  invoice MVP and binding spec), and it contradicts Constitution I. It also makes the round-trip
  guarantee untestable as a public contract.
- *Expose model but not the codec* (consumer writes its own JSON): rejected — duplicates the
  format, breaks the single-source-of-truth and versioning guarantees of Constitution V.

---

## D3 — Editing & undo/redo architecture

**Decision**: A public `JetReportDesignerController` (a `ChangeNotifier`) is the single state
seam. It holds the current immutable `ReportTemplate`, the current `Selection`, an in-memory
`Clipboard`, and an `EditHistory`. Every state-changing edit is an **`EditCommand`** that maps a
`DesignerDocument` (an immutable `(template, selection)` pair) to the next `DesignerDocument`.
The history keeps two stacks of `DesignerDocument` **snapshots**; applying a command pushes the
prior document onto the undo stack and clears the redo stack. Undo/redo move documents between
the stacks and re-notify.

**Rationale**:
- The domain is immutable with value equality, so a `DesignerDocument` snapshot is just two object
  references — **O(1) to store, exact to restore**. This makes FR-017 ("undo/redo restore both the
  model *and* a coherent selection", no fixed limit) almost free and removes the bug-prone need
  to hand-author inverse operations.
- Modelling edits as named `EditCommand`s (create/move/resize/delete/reorder/clipboard/
  setGeometry/setText/align/distribute) gives a clean, testable unit per FR and a natural label
  for each history entry (and future "Undo *Move*" affordances), satisfying the spec's
  *Edit/Command* entity.
- Snapshots vs. inverse-commands: at ≤200 elements and session-scoped history, snapshot memory is
  negligible (immutable structural sharing of unchanged elements; only changed bands' lists are
  rebuilt). Simplicity and correctness win.

**Live-gesture coalescing**: a drag or resize is **one** history entry, not one per pointer move.
The controller exposes `beginInteraction()` / `updateInteraction(...)` / `commitInteraction()` /
`cancelInteraction()`. During an interaction the canvas previews changes on an overlay (D5) and
the model is untouched; `commit` produces a single new document + single history entry on pointer
release (matching acceptance US1.3 "on release, its model position updates" and US2.1).

**Element identity (FR-004)**: the controller owns a monotonic `int` sequence; a new element gets
`'<typeKey><n>'` (e.g. `text1`, `shape2`). On `open`, the sequence is seeded past the largest
numeric suffix present so reopened documents never collide. `id` uniqueness within the template is
asserted in tests.

**Domain additions required** (small, in the domain seam, test-first):
- `ReportElement.withBounds(JetRect)` — an abstract method each subtype implements, returning a
  copy with new `bounds`. This is the polymorphic move/resize primitive used by every geometry
  edit and is broadly useful (engine/binding specs). Lives in domain because geometry is a
  first-class model concern.
- `TextElement.copyWith({String? text})` — for inline text editing (FR-019).
- `ReportBand.copyWith({List<ReportElement>? elements})` and
  `ReportTemplate.copyWith({List<ReportBand>? bands, String? name})` — structural rebuild helpers
  for the edit layer (changing one band's element list / replacing bands).
These are additive, non-breaking, and unit-tested (Constitution III).

**Alternatives considered**:
- *Mutable editing model* separate from the immutable domain: rejected — duplicates the model,
  needs a sync/serialize bridge, and discards the free-undo property of immutability.
- *Inverse-command undo* (each command stores how to revert): rejected — more code, more bugs,
  no benefit over snapshots given immutability and the modest element count.

---

## D4 — Canvas interaction model (selection, move, resize, marquee, hit-testing, zoom/pan)

**Decision**: The center surface hosts an interactive **`DesignCanvas`** built from Flutter
pointer/gesture primitives + `CustomPaint`, themed via `ShadTheme`. It maintains:

- A **view transform** (`CanvasViewTransform`): a single uniform `scale` (zoom) + `pan` offset
  mapping **page points ↔ screen pixels**. All hit-testing converts the pointer to page
  coordinates through the inverse transform, guaranteeing pointer-accurate placement at every zoom
  (FR-020 / SC-006).
- A **design-time layout map**: for the current template, each element's absolute page `JetRect`
  and owning band (computed by `design_time_layout.dart`, the same geometry feeding the
  design-time frame in D1). Hit-testing is point-in-rect against this map in **z-order
  (last-painted = top-most first)**, so clicks pick the top element (overlap edge case);
  repeated/alt-click cycles downward (assumption in spec).
- **Selection handles** with hit areas ≥ visual size (8 px visual / 16 px grab) so tiny elements
  stay grabbable (edge case). Eight handles (corners + edges) drive resize; the body drives move.
- **Marquee**: a drag starting on empty canvas draws a rubber-band rect; elements fully enclosed
  become the selection on release (FR-006). Shift-click adds/removes; `Esc`/empty-click clears.
- **Constraint (FR-010)**: during move/resize the committed bounds are clamped so the element stays
  within its owning band and the page content area (no off-page placement).

**Rationale**: A report canvas needs sub-pixel-accurate, zoom-correct direct manipulation that
generic widgets (`Draggable` of opaque widgets) can't give for arbitrary handles, marquee, and
snapping. A single page↔screen transform is the standard, well-understood basis and keeps
hit-testing and rendering in the same coordinate space.

**Drag-and-drop create (FR-001/FR-002)**: toolbox entries become `Draggable<DesignerToolType>`
payloads; the canvas is a `DragTarget`. On drop, the global position is converted to page
coordinates, the target band is found (or the drop is rejected/routed to the nearest valid band —
edge case), and a `CreateElementCommand` adds a typed element at the drop point with a per-type
default size (D7). Click-to-place (toolbox tap → place at a default spot / next click) is offered
as the keyboard/no-drag path.

**Alternatives considered**:
- *`InteractiveViewer` for zoom/pan*: usable for pan/zoom but it owns the transform and complicates
  precise pointer→page mapping and overlay alignment; a hand-rolled transform is clearer and keeps
  one source of truth. May still wrap content in a `Transform`/`Viewport` for scrolling.
- *Hit-test against painted primitives' `elementId`*: rejected as the primary path — empty text,
  transparent shapes, and handle grabbing need bounds-based hit-testing, not pixel coverage.
  Primitive `elementId` remains available as a secondary aid.

---

## D5 — Performance strategy (SC-007: ~200 elements, drag 20+ at ~60 fps)

**Decision**: Three-layer paint with a cached base:
1. **Base layer** — the committed design-time `PageFrame` rasterized to a cached `ui.Picture`
   (built once per committed model change after async `prepare`, D1). Pan/zoom redraw the canvas
   by replaying the cached picture under the new transform — no re-emit, no re-prepare.
2. **Interaction layer** — during a live move/resize the dragged subset is excluded from (or drawn
   over) the base and painted as lightweight ghosts that follow the pointer; only the selection
   (≤ document) is re-evaluated per frame, so frame cost scales with the *selection*, not the
   document.
3. **Overlay layer** — handles, marquee, snap guides, hover/selection outlines, drop indicator —
   all cheap vector draws.

`shouldRepaint` is keyed on (transform, selection, interaction-delta, model-revision) so idle
frames cost nothing.

**Rationale**: The expensive work (text measurement, image decode, primitive emission) happens
only on commit, off the interaction hot path. Replaying a cached `ui.Picture` and drawing a
handful of overlay rects is trivially ≥60 fps for 200 elements. This directly targets SC-007's
"drag 20+ without perceptible lag."

**Validation**: a widget/perf test builds a 200-element template, drives a multi-select drag, and
asserts frame-build time budget / no exceptions; goldens cover static fidelity.

**Alternatives considered**: rebuilding the immutable template and re-emitting the whole frame per
pointer move — rejected (O(elements) per frame; defeats the budget and spams history).

---

## D6 — Cross-panel sync, inline editing, keyboard, localization

**Decision (sync, FR-018)**: The `JetReportDesignerController` is provided down the tree via an
`InheritedNotifier`. The **Outline** and **Properties** panels (currently static placeholder
trees from 002) are rebuilt as model-driven `ListenableBuilder`s over the controller: canvas
selection → Outline highlight + Properties reflection; Outline row tap → `controller.select(...)`
→ canvas handles + scroll/zoom into view (FR-018, edge case "off-screen when selected"). The
**Data Source** panel is untouched (Out of Scope).

**Decision (Properties editing, FR-019)**: Properties shows the selection's geometry as numeric
x/y/width/height fields (`ShadInput`, reusing the existing `_NumberField`/stepper widgets) bound to
`SetGeometryCommand`; for a single text element it also edits text. Inline canvas text editing:
double-click a text element overlays a `ShadInput`/`TextField` positioned over the element at the
current scale; commit on Enter/blur via `SetTextCommand`. All such edits reflect immediately and
are undoable.

**Decision (keyboard, FR-016)**: A `Focus` node owns the canvas; a `Shortcuts`+`Actions` map scoped
to that node binds nudge (arrows / Shift+arrows), delete, undo/redo, copy/cut/paste, duplicate,
select-all. Because the shortcuts are scoped to the canvas focus node, a focused panel `TextField`
or Properties input keeps its keystrokes (edge case "MUST NOT hijack typing") — Flutter's focus
traversal routes keys to the focused descendant first.

**Decision (localization, FR-024)**: All new affordances (context-menu items, tooltips,
accessible labels, drop hints, align/distribute/z-order action names) add keys to
`lib/src/designer/l10n/jet_print_en.arb` (+ `_de.arb`, `_tr.arb`), regenerated via `flutter
gen-l10n` (config in `l10n.yaml`, English first = fallback). Strings are read through
`JetPrintLocalizations.of(context)`. Coverage + fallback are asserted by extending the existing
`localization_*_test.dart` suite.

**Rationale**: Reuses the exact seams 002 established (the `InheritedNotifier` controller pattern,
the ARB→gen-l10n pipeline, existing shadcn property widgets), so the interactive layer slots into
proven infrastructure with no new patterns. Scoped focus is the idiomatic Flutter answer to the
"don't hijack typing" requirement.

**Alternatives considered**: a global `RawKeyboardListener` — rejected (would need manual focus
checks to avoid hijacking panel inputs; scoped `Shortcuts` does this for free). A separate
state-management package (Riverpod/Bloc) — rejected (Constitution: minimal deps; a `ChangeNotifier`
+ `InheritedNotifier` is sufficient and dependency-free).

---

## D7 — Behavioral tunables (spec fixes behavior; planning fixes the defaults)

Per the spec's *Units & tunables* assumption, behavior is fixed by the spec and these concrete
desktop defaults are chosen now (all in report **points** unless noted; centralized as named
constants so they are easy to tune and test):

| Tunable | Default | Notes |
|---|---|---|
| Grid spacing | 8 pt | Snap-to-grid increment; honors the top bar grid toggle (FR-011). |
| Snap threshold | 6 px (screen) | Converted to points via the live zoom so snapping feels uniform at any zoom (FR-011 / SC-004). |
| Snap targets | grid, sibling edges + centers, band + page bounds | Guides drawn for the matched target. |
| Snap bypass | hold `Alt`/`Option` | Suspends snapping for the gesture (FR-011, US2.3). |
| Nudge step | 1 pt (arrow) / 10 pt (Shift+arrow) | FR-016. |
| Default size — text | 120 × 18 pt | Sensible click/drop default (FR-002, zero-drag edge case). |
| Default size — shape (rect) | 120 × 60 pt; line 120 × 1 pt box | |
| Default size — image | 100 × 100 pt | |
| Default size — barcode | 120 × 60 pt (QR/DataMatrix 80 × 80) | |
| Min element size | 4 × 4 pt | Resize floor (FR-009); lines may collapse one axis. |
| Paste/duplicate offset | +8, +8 pt | Offsets copies from originals (FR-015). |
| Zoom range / step | 25 %–400 %, 10 % step | Reuses the existing top bar `_zoomMin/_zoomMax/_zoomStep`. |
| Handle visual / hit size | 8 px / 16 px | Hit ≥ visual (tiny-element edge case). |
| Z-order semantics | `band.elements` order = paint order; later = on top | bring-forward/back = list reorder (FR-013). |

**Rationale**: Values mirror established desktop report/diagram designers (the spec's "industry
grade" reference) and the constants 002 already chose for zoom. They are defaults, not contracts —
the spec fixes the *behavior* (snapping happens, nudge has two steps), and these make it concrete
and testable.

---

## D8 — Persistence seam (FR-022, keeping the library headless)

**Decision**: The **library stays I/O-free** (no `dart:io`); file open/save is a **consumer**
concern. The top bar's Save/Open actions invoke controller-level hooks (`onSaveRequested` /
`onOpenRequested`, or equivalent callbacks on `JetReportDesigner`) that hand the consumer the
current `ReportTemplate` (for save) or accept one (for open). The **tester app** implements those
hooks: it uses a file-picker dependency to choose a path and `JetReportFormat.encodeJson` /
`decodeJson` to write/read the JSON. The lossless guarantee (FR-003 / SC-002) is verified as a
pure-Dart contract test on `JetReportFormat` (edit → `controller.template` → encode → decode →
`==`), independent of any UI or filesystem.

**Rationale**: Constitution Technology Standards require platform-agnostic, headless rendering and
"swappable abstractions"; embedding `dart:io` in the published package would break web/embedding
targets. Keeping I/O in the consumer matches how 002 already treats the app as a pure consumer and
keeps the round-trip testable without a filesystem.

**Tester-app dependency**: a maintained, permissively-licensed file picker (e.g.
`file_selector`, first-party Flutter) added to **`apps/jet_print_tester`** only — not to the
published `packages/jet_print`. This respects the "minimal/justified deps" rule for the library
while letting the consumer demonstrate open/save.

**Alternatives considered**: a `dart:io`-based save inside the library — rejected (platform
coupling, violates headless standard). Auto-save / recent-files / new-blank — explicitly Out of
Scope.

---

## Resolved unknowns summary

| Technical Context item | Resolution |
|---|---|
| How to render design-time fidelity without divergent code | D1 — reuse `ElementRenderer.emit` + `CanvasPainter`; thin non-paginated band layout |
| Whether/what to make public for model + save/open | D2 — export model + `JetReportFormat` codec facade |
| Edit + undo/redo model on an immutable domain | D3 — `ChangeNotifier` controller + command + document snapshots; add `withBounds`/`copyWith` |
| Selection / move / resize / marquee / hit-test / zoom-pan | D4 — `DesignCanvas` with a single page↔screen transform |
| 60 fps with 200 elements / 20-element drag | D5 — cached base `ui.Picture` + lightweight interaction/overlay layers, commit-on-release |
| Cross-panel sync, inline edit, keyboard, l10n | D6 — `InheritedNotifier` controller; scoped `Shortcuts`; ARB additions |
| Grid/snap/nudge/default-size/zoom values | D7 — fixed desktop defaults as named constants |
| Open/save without coupling the library to a filesystem | D8 — headless library + consumer-driven file I/O via `JetReportFormat` |

No `NEEDS CLARIFICATION` markers remain.
