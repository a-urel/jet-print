# Implementation Plan: Shape Gallery in Properties Pane

**Branch**: `020-shape-gallery` | **Date**: 2026-06-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/020-shape-gallery/spec.md`

## Summary

Today a `ShapeElement` can only be a **line** or a **rectangle**
([`ShapeKind`](../../packages/jet_print/lib/src/domain/elements/shape_element.dart#L9)), and the
Properties pane offers no way to change which form it is. This feature adds a **visual shape gallery**
to the Properties pane that, for a selected shape, shows eight thumbnails — line, rectangle, ellipse,
triangle, diamond, pentagon, hexagon, star — highlights the active one, and switches the shape's form
in one undoable click while preserving its bounds and fill/stroke.

The work rides four seams that already exist and were proven by 018 (page properties) and 012 (export):

1. **One geometry source, consumed everywhere (WYSIWYG, IV).** A new private
   `shape_path.dart` in the rendering layer exposes `shapePath(ShapeKind, JetRect) → List<PathCommand>`.
   The six new polygonal forms are pure straight-line polygons; the **ellipse is a high-segment
   (64) polygon** so it needs no curve primitive. `ShapeElementRenderer.emit` gains a single branch
   that emits a [`PathPrimitive`](../../packages/jet_print/lib/src/rendering/frame/primitive.dart#L183)
   from `shapePath(...)` for every form that isn't the special-cased rectangle/line. Because
   `PathPrimitive` already replays identically through `CanvasPainter` and `PdfPainter`, canvas,
   preview, and export agree **with no new painter code and no forked render path** (FR-008, SC-003).
   The gallery thumbnails paint through the *same* `shapePath`, so the picker icon is the shape.

2. **One undoable controller op.** `JetReportDesignerController.setShapeKind(String id, ShapeKind kind)`
   commits a new `SetShapeKindCommand` through the existing
   [`_commit`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L975)
   path. Picking the active form is a no-op the command itself reports (returns `before`), so
   `_commit` records no history and fires no notification (FR-005, FR-006, SC-005). Switching **away
   from line** resets the line-only `flipDiagonal`; switching **to** any known form clears any
   preserved unknown-form name (edge cases in spec).

3. **Lossless unknown-form round-trip (V, FR-009).** `ShapeElement` gains an optional
   `String? unknownForm`. The codec's `fromJson` tries `ShapeKind.values.byName(name)`; on an
   unrecognized name it sets `kind = rectangle` (safe render default) **and** `unknownForm = name`.
   `toJson` writes `unknownForm` back as `kind` when present, so re-saving a report authored by a
   *newer* version does not discard its form. Known forms still serialize exactly as before
   (`kind: <enum name>`), so `kReportSchemaVersion` stays **1**, no migration, pre-feature reports
   load byte-for-byte unchanged (FR-007, SC-004).

4. **The Properties section, type-gated.** `_elementInspector` already branches `if (element is
   TextElement)` / `if (element is ImageElement)`; a new `if (element is ShapeElement)` adds a
   `_ShapeGallery` section. The gallery is absent for text/image/barcode and for no selection
   (FR-010). Each thumbnail is a `Semantics(button, label: <localized form name>)` reachable and
   activatable by keyboard (FR-012), and all eight names plus the section label are localized in
   en/de/tr.

See [research.md](research.md) for the grounded decisions (ellipse-as-polygon and segment count;
PathPrimitive reuse over a new curve primitive; `unknownForm` preservation over a string-typed form;
single `setShapeKind` op; thumbnails share the renderer geometry), [data-model.md](data-model.md) for
the entities (the enum extension, the `unknownForm` field + `copyWith`, `SetShapeKindCommand`, the
`shapePath` form table), [contracts/shape-gallery.md](contracts/shape-gallery.md) for the behavioral
contracts + test groups, and [quickstart.md](quickstart.md) for the end-to-end walk.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only. Rendering: `PathPrimitive` + `MoveTo`/`LineTo`/`ClosePath`
(already painted by `CanvasPainter` and `PdfPainter`). Designer UI: `shadcn_ui ^0.54.0`,
`flutter` (`CustomPaint` for thumbnails, `Focus`/`Semantics`), `lucide` icons — the same widgets the
Properties panel's existing sections use. **No new deps.**
**Storage**: `ShapeElement` serializes via
[`shape_element_codec.dart`](../../packages/jet_print/lib/src/domain/serialization/shape_element_codec.dart)
inside the report JSON (`kReportSchemaVersion = 1`). This feature adds new `ShapeKind` enum values
(serialized by `.name`, exactly like the existing two) plus an optional `unknownForm` write-back path
for unrecognized forms. **No schema-version bump, no migration**: known forms are wire-identical to
today, and the unknown-form handling is purely a defensive load/round-trip path.
**Testing**: `flutter test packages/jet_print` (from repo root). Unit — `shapePath` produces a closed
polygon inscribed in arbitrary bounds for each form (vertex count, within-bounds, degenerate 1×1 box
does not throw); `ShapeElement.copyWith`/equality; codec round-trips every known form and **preserves
an unknown form name** (read rectangle+unknownForm → write original); `SetShapeKindCommand` is one
undoable, notifying step, a no-op when the form is unchanged, resets `flipDiagonal` off line, clears
`unknownForm` on an explicit pick. Widget — the gallery appears only for a selected shape (not
text/image/barcode/none), highlights the active form, a click changes the model in one undo step,
re-click of the active form records nothing, items carry localized accessible names and are keyboard
operable across en/de/tr. Golden — a page containing each new form renders identically on canvas,
preview, and export (new goldens for the new forms; existing line/rectangle goldens stay
byte-identical). Regression — codec, layout, existing property/golden suites green;
`public_api_test.dart` records the enum additions + `setShapeKind` + `ShapeElement.copyWith`/`unknownForm`.
**Target Platform**: Designer Properties UI (Flutter desktop/web). Reference env: macOS desktop
playground (`apps/jet_print_playground`).
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` + consumer app
`apps/jet_print_playground`.
**Performance Goals**: No new budget. `setShapeKind` is one `_commit`. Each shape emits one
`PathPrimitive`; the 64-segment ellipse is a one-time list build per frame, negligible against the
cached element picture. Thumbnails are tiny `CustomPaint`s rebuilt only when the selected shape
changes.
**Constraints**: WYSIWYG (IV) — one `shapePath` feeds the one renderer that canvas/preview/export all
share; **no parallel render path** is introduced, and the gallery icon reuses the same geometry so the
picker cannot drift from the result. Layer boundary (II) — the domain gains only the enum values, the
`unknownForm` field, and `copyWith` (no rendering/UI import). `shapePath` lives in the **rendering**
layer (it produces rendering primitives); the renderer and the designer's thumbnail both consume it
(designer already depends on rendering). The command/gallery live in the **designer** seam. Minimal
surface (I) — one controller method + an additive enum + one nullable field + `copyWith`; `shapePath`,
the command, and the gallery stay private. Backward-compat (V) — known forms wire-identical, unknown
forms preserved, schema stays 1. l10n (FR-012) — eight form names + section label in en/de/tr.
**Scale/Scope**: 6 new `ShapeKind` values · `ShapeElement.copyWith` + `unknownForm` field · defensive
codec read + write-back · 1 `shapePath` geometry file (8-form table) · 1 renderer branch · 1 new
command (`SetShapeKindCommand`) + 1 controller op (`setShapeKind`) · the `_ShapeGallery` Properties
section + thumbnail painter · ~9 new ARB keys × 3 locales · the test matrix above · 3 user stories
(P1 pick form, P2 undo/redo, P3 persist across save/preview/export).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | New public surface is minimal and additive: six new `ShapeKind` enum values, `JetReportDesignerController.setShapeKind(id, kind)` (undoable, mirrors `setGeometry`/`setPageFormat`), and `ShapeElement.copyWith` + the `unknownForm` field on an already-public immutable type. `shapePath`, `SetShapeKindCommand`, and the `_ShapeGallery` widget stay **private** under `src/`. `public_api_test` records the additions. No host-app coupling. |
| II | Layered & Extensible Architecture | ✅ PASS | Dependencies point inward. The **domain** change is additive only (enum values, `unknownForm`, `copyWith`) — no Flutter/UI/render import enters it. `shapePath` lives in the **rendering** layer (it emits `PathCommand`s); the renderer and the designer thumbnail both consume it (designer→rendering is already allowed). The command + gallery live in the **designer** seam. New forms were added through the existing renderer extension point — the painter core was not touched (FR-002's "cheap to add more"). `layer_boundaries_test` stays green. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green→refactor. The exhaustive `switch (el.kind)` makes each unhandled new form a **compile-time red**. Load-bearing behaviors are pinned by failing tests first: `shapePath` geometry per form (closed, inscribed, degenerate-safe); codec preserves an unknown form name; `setShapeKind` is one undoable step, no-op-safe, resets `flipDiagonal`, clears `unknownForm`. Widget tests drive the gallery (gating, highlight, click→undo, no-op, a11y, l10n) before it exists. No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | Canvas (`design_time_frame`), preview, and export (`jet_report_exporter`) all paint the **same** `PathPrimitive` emitted from the **one** `shapePath`; this feature forks no render path and adds no painter code, so every form is identical across all three (SC-003). New goldens prove each form propagates; existing line/rectangle goldens stay byte-identical. The gallery thumbnail reuses `shapePath`, so the picker cannot diverge from the rendered shape — covered by a widget test, not by report goldens. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | Known forms serialize as `kind: <enum name>` exactly as today; the six additions ride that mechanism. `kReportSchemaVersion` stays **1**, no migration. An unrecognized `kind` loads as a rectangle while `unknownForm` retains the original string, and `toJson` writes it back — a **lossless round-trip** (FR-009, SC-004). A codec test proves pre-feature reports open byte-for-byte unchanged and a forward-form report survives load→save. |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on `setShapeKind` (single-undo + no-op semantics), the new `ShapeKind` values, `ShapeElement.copyWith`/`unknownForm`, and `shapePath`; `CHANGELOG.md` updated. All eight form names + the section label localized in en/de/tr (FR-012). The playground demonstrates selecting a shape, picking a hexagon/star, undo/redo, and canvas+preview+export agreeing. Zero analyzer warnings; `dart format` clean. |

**Result: PASS — no violations.** Two items recorded in *Complexity Tracking* for reviewer visibility:
(a) the ellipse is rendered as a 64-segment polygon rather than a true curve; (b) a single
`setShapeKind(ShapeKind)` op rather than exposing the gallery's internal selection state.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md), [contracts/shape-gallery.md](contracts/shape-gallery.md),
and [quickstart.md](quickstart.md): still **PASS**. Public surface stayed at one method + an additive
enum + one field + `copyWith`; `shapePath`/command/gallery stayed private; the render path was not
forked and no painter code was added (the new forms reuse `PathPrimitive`); schema stayed 1 with a
lossless unknown-form round-trip. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/020-shape-gallery/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — ellipse-as-polygon + segment count; PathPrimitive reuse vs new curve; unknownForm preservation vs string form; single setShapeKind op; thumbnails share renderer geometry
├── data-model.md        # Phase 1 — ShapeKind extension; ShapeElement.copyWith + unknownForm; codec read/write-back; shapePath form table; SetShapeKindCommand; NO schema change
├── quickstart.md        # Phase 1 — end-to-end: select shape → pick hexagon/star → undo/redo → save/reload → preview/export agree
└── contracts/
    └── shape-gallery.md # Phase 1 — behavioral contracts (gallery gating, highlight, pick, no-op, undo, line/flip coherence, persistence, unknown-form round-trip, a11y/l10n) + test groups
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/
│   ├── jet_print.dart                                   # CHANGE: re-export already covers ShapeElement/ShapeKind/controller;
│   │                                                    #         setShapeKind is a method, copyWith/unknownForm on exported type — verify no new export line needed
│   └── src/
│       ├── domain/
│       │   ├── elements/
│       │   │   └── shape_element.dart                   # CHANGE: + 6 ShapeKind values (ellipse, triangle, diamond, pentagon, hexagon, star); + String? unknownForm field; + copyWith; update ==/hashCode/withBounds/toString
│       │   └── serialization/
│       │       └── shape_element_codec.dart             # CHANGE: fromJson tolerant parse (unknown → rectangle + unknownForm); toJson writes unknownForm back as kind when set
│       ├── rendering/
│       │   └── elements/
│       │       ├── shape_path.dart                      # NEW (private): shapePath(ShapeKind, JetRect) → List<PathCommand>; per-form polygon table; ellipse = 64-seg; regular polygons inscribed; star point-count + inner/outer ratio
│       │       └── renderers/
│       │           └── shape_element_renderer.dart      # CHANGE: rectangle→RectPrimitive, line→LinePrimitive (unchanged); all other forms → PathPrimitive(commands: shapePath(...))
│       └── designer/
│           ├── controller/
│           │   ├── jet_report_designer_controller.dart  # CHANGE: + void setShapeKind(String id, ShapeKind kind) → _commit(SetShapeKindCommand)
│           │   └── commands/
│           │       └── set_shape_kind_command.dart      # NEW: EditCommand swapping kind (preserve style; flipDiagonal off when kind != line; clear unknownForm); returns before when unchanged
│           ├── layout/panels/
│           │   └── properties_panel.dart                # CHANGE: in _elementInspector add `if (element is ShapeElement)` → SectionLabel + _ShapeGallery (8 thumbnails via shapePath, active highlight, Semantics, keyboard); private _ShapeThumbnail CustomPainter
│           └── l10n/
│               ├── jet_print_en.arb                     # CHANGE: + propertiesShape + 8 form-name keys (+@desc)
│               ├── jet_print_de.arb                     # CHANGE: same keys, German
│               └── jet_print_tr.arb                     # CHANGE: same keys, Turkish
│                                                        #   (regenerate jet_print_localizations*.dart)
└── test/
    ├── domain/
    │   └── elements/
    │       └── shape_element_test.dart                  # NEW/EXTEND: copyWith per-field; equality incl. unknownForm
    ├── domain/serialization/
    │   └── shape_element_codec_test.dart                # NEW/EXTEND: round-trip every known form; unknown kind → rectangle + unknownForm; write-back lossless; pre-feature report unchanged
    ├── rendering/elements/
    │   ├── shape_path_test.dart                         # NEW: each form closed + inscribed in arbitrary bounds; vertex counts; 1×1 / 1×N degenerate does not throw
    │   └── shape_element_renderer_test.dart             # EXTEND: each new form emits a PathPrimitive matching shapePath; rectangle/line cases unchanged
    ├── designer/
    │   ├── controller/
    │   │   └── set_shape_kind_command_test.dart         # NEW: single undo/redo; no-op when unchanged; notifies once; flipDiagonal reset off line; unknownForm cleared on pick; codec round-trip
    │   ├── properties_editor_test.dart                  # EXTEND: gallery present only for shape (not text/image/barcode/none); highlights active; click→one undo step; re-click active records nothing; en/de/tr
    │   ├── accessibility_semantics_test.dart            # EXTEND: gallery items carry localized name + button role; keyboard reachable
    │   └── goldens/
    │       └── shape_forms_*.png                        # NEW goldens: each new form identical across canvas/preview/export
    └── public_api_test.dart                             # UPDATE: record new ShapeKind values + setShapeKind + ShapeElement.copyWith/unknownForm
```

**Structure Decision**: Existing workspace monorepo, no new top-level structure. The domain stays
UI-free and render-free — only the additive enum values, the `unknownForm` field, and `copyWith` land
there. The single shape **geometry** lives once in the rendering layer (`shape_path.dart`), consumed
by both the renderer (canvas/preview/export) and the designer thumbnail, guaranteeing the picker and
the result cannot diverge. The command and the `_ShapeGallery` section live in the **designer** seam
beside their precedents (`set_format_command.dart`, the type-gated sections in `properties_panel.dart`).
The controller gains exactly one mutator (`setShapeKind`) routed through the existing `_commit`/history
path so every form change is one undoable step.

## Complexity Tracking

> No Constitution **violations** to justify. Two tracked items for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Ellipse rendered as a 64-segment polygon, not a true curve | The path primitive set is `MoveTo`/`LineTo`/`ClosePath` — no curve command. Adding a `CubicTo` would expand the sealed `PathCommand` set **and** require new code in every painter (`CanvasPainter`, `PdfPainter`) plus golden churn — surface this feature does not need. | A 64-segment inscribed polygon is visually smooth at report DPI and in PDF/PNG export, and reuses the existing `LineTo` replay so WYSIWYG holds with zero painter changes. Segment count is a single tunable; revisited only if a fidelity issue is observed (recorded in research.md). |
| Single `setShapeKind(ShapeKind)` op rather than exposing gallery selection state | A form change is one conceptual edit to one immutable element; the gallery hands the controller the chosen `ShapeKind` and nothing else. | Keeps the public surface minimal (I), centralizes the no-op / `flipDiagonal`-reset / `unknownForm`-clear logic in one command (FR-005, edge cases), and yields exactly one undo step per pick (FR-006). |
