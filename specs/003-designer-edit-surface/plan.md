# Implementation Plan: Designer Edit Surface — Direct-Manipulation Element Editing

**Branch**: `003-designer-edit-surface` | **Date**: 2026-06-08 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-designer-edit-surface/spec.md`

## Summary

Turn the **design surface** of the report designer (a static A4 placeholder from spec 002) into an
**interactive WYSIWYG canvas**. Report authors drag element types (text/shape/image/barcode) from
the toolbox onto bands, then select, move, resize, align (with grid/sibling/band snapping +
guides), multi-select (marquee, shift-click), reorder (z-order), nudge, copy/paste/duplicate,
delete, and inline-edit text — every action against an **in-memory `ReportTemplate`** with
**unlimited session undo/redo** that restores model *and* selection, and a **lossless** save/open
round-trip through the existing JSON file format.

Technical approach (from [research.md](research.md)):

1. **Reuse the existing render pipeline for fidelity** — the design canvas paints elements via the
   unchanged `ElementRenderer.emit()` → `FrameBuilder` → `CanvasPainter` path; only a thin,
   non-paginated *design-time band layout* is new (Constitution IV — no divergent rendering). The
   committed frame is cached as a `ui.Picture`; pan/zoom/drag only re-blit + draw overlays, hitting
   the 200-element / 60 fps target (SC-007).
2. **Immutable-model editing** — a public `JetReportDesignerController` (`ChangeNotifier`) holds
   the template, selection, clipboard, and an undo/redo history of immutable `(template, selection)`
   snapshots. Edits are `EditCommand`s mapping one snapshot to the next; live gestures coalesce to
   one history entry on release. Snapshots make FR-017 correct by construction.
3. **Public-API expansion (the central commitment)** — hosting/saving a model forces exposing the
   report model graph + a `JetReportFormat` codec facade from the single entry point, **reversing
   the 002 non-goal**. Mandated by FR-003/FR-022 and Constitution I/V; scoped to types reachable
   from `ReportTemplate`.
4. **Reuse the 002 seams** — the `InheritedNotifier` controller pattern, shadcn chrome widgets, the
   ARB→gen-l10n pipeline (en/de/tr + English fallback), and the keyed test harness. The Outline and
   Properties panels become model-driven (selection sync + geometry/text editing); the Data Source
   panel is untouched (Out of Scope).

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK constraint, `pubspec.yaml`), sound
null-safety.
**Primary Dependencies**: Flutter SDK (`flutter`, `flutter_localizations`); `intl` (gen-l10n);
`shadcn_ui ^0.54.0` (chrome — buttons/inputs/menus/tabs/cards/tooltips, theme). The interactive
canvas is built from Flutter `CustomPaint` + pointer/gesture/focus primitives — **no new library
dependency**. The **playground app only** adds a maintained, permissive file picker (e.g.
`file_selector`) for open/save (research D8); the published package adds none.
**Storage**: The versioned `ReportTemplate` JSON (Constitution V) via the existing
`report_codec.dart`, newly surfaced through a public `JetReportFormat` facade. Library performs no
filesystem I/O (headless); the consumer owns file reads/writes.
**Testing**: `flutter test` — unit (controller/commands/history/codec round-trip/domain helpers),
widget (drop-create, select/move/resize, marquee, snapping, z-order, clipboard, keyboard,
inline-edit, cross-panel sync, zoom accuracy), localization (en/de/tr + fallback), goldens
(design surface light/dark via the shared render pipeline), and a 200-element drag perf smoke. The
existing architecture (layer-boundary) + encapsulation tests stay green.
**Target Platform**: macOS desktop (playground app); the library stays platform-agnostic/headless.
Input target is mouse + keyboard (touch/stylus not this iteration).
**Project Type**: Dart pub workspace monorepo — reusable library (`packages/jet_print`, the
product) + sample/playground desktop app (`apps/jet_print_playground`, a consumer).
**Performance Goals**: ~200 elements/design at ~60 fps (≈16 ms/frame); a ≥20-element selection
drags without perceptible lag (SC-007). Achieved by caching the committed frame as a `ui.Picture`
and keeping per-frame work proportional to the active selection (research D5).
**Constraints**: Constitution IV — element rendering MUST reuse the shared pipeline (no parallel
draw code). Constitution I — all consumer access through the single public entry point; `src/`
stays private (encapsulation test). Domain seam stays UI-free (layer-boundary test). Zero analyzer
warnings; `dart format` clean; no skipped tests; goldens current. Keyboard shortcuts MUST NOT
hijack typing in focused panel inputs (scoped `Shortcuts`). All new visible text localized
(en/de/tr, English fallback); new affordances keyboard-operable with accessible names.
**Scale/Scope**: 1 changed public widget (`JetReportDesigner` gains optional params) + 1 new public
controller + 1 new serialization facade + the `ReportTemplate`-reachable model graph exported;
~4 toolbox element types; geometry + text editing only (full property suite deferred); 6 user
stories (P1–P4); ~11 contract/test groups (contracts/designer-edit-api.md §7).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | All new capability ships as library symbols (`JetReportDesignerController`, `JetReportFormat`, the `ReportTemplate` model graph) from the single entry point `lib/jet_print.dart`; the playground app consumes them as an external consumer (drives file I/O itself). Internals (canvas, commands, layout, design-time frame) stay under `src/`, guarded by the encapsulation test. The public-surface *expansion* is deliberate and required by FR-003/FR-022 (research D2), not incidental coupling. |
| II | Layered & Extensible Architecture | ✅ PASS | Editing lives in the **designer** seam; it depends inward on `domain` (model) and `rendering` (renderers/painter), never the reverse. The domain seam stays UI-free — the only domain additions are pure value-copy helpers (`withBounds`/`copyWith`), keeping the layer-boundary test green. New element types still flow through the existing codec + renderer registries (open/closed); the designer reads them generically. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Phase 2 writes tests before code for every unit (commands/history/controller/codec round-trip/domain helpers) and behavior (drop/select/move/resize/marquee/snap/z-order/clipboard/keyboard/inline-edit/sync/zoom). Suite must be green, no skips. Contracts §7 enumerates the test-first set. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | The canvas renders element appearance through the **unchanged** `ElementRenderer.emit` + `CanvasPainter` pipeline; only non-paginated band-stacking geometry is design-specific (research D1). No parallel/divergent element-drawing code. Design-surface goldens (light/dark) extend the WYSIWYG harness and lock fidelity. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | Save/open use the existing versioned, migration-aware codec, surfaced as `JetReportFormat` (stamps `schemaVersion`, runs migrations, preserves unknown elements/fields). No schema change is introduced; the lossless round-trip is contract-tested (SC-002). Making the format public is the act Constitution V anticipates (the format is a user-owned contract). |
| VI | Documentation & Developer Experience | ✅ PASS | New public symbols carry dartdoc (controller ops, designer params, codec, model types); playground app stays runnable and gains working open/save + interaction; `CHANGELOG.md` updated; `dart format` + strict analysis enforced (generated l10n excluded as already configured). |

**Initial gate: PASS.** The one structurally significant move — exposing the model + codec — is
**spec-mandated** (FR-003: in-memory model; FR-022: open/save via the existing serialization) and
**constitution-aligned** (I makes the library the product; V treats the format as a public
contract). It is therefore not unjustified complexity. No Complexity Tracking entries required.
The single new dependency (`file_selector`) is confined to the **playground app**, not the published
package, honoring the minimal-deps rule.

### Post-Design re-check (post-Phase-1)

**PASS.** The Phase 1 design holds every gate:

- **IV reaffirmed**: [data-model.md](data-model.md) §4 + [research.md](research.md) D1 keep all
  element drawing in the shared renderers/`CanvasPainter`; the new `DesignTimeLayout`/design-time
  frame only positions bands (no element rasterization of its own). Goldens enforce it.
- **I/II reaffirmed**: [contracts/designer-edit-api.md](contracts/designer-edit-api.md) confines
  the public surface to the controller + codec + `ReportTemplate`-reachable model; all canvas,
  command, history, and layout types stay private (`src/designer/...`). Domain additions are pure
  value copies → layer-boundary + encapsulation tests stay green.
- **III/V/VI reaffirmed**: contracts §7 lists the test-first contract set incl. the lossless
  round-trip; no schema bump; dartdoc + changelog + analysis/format gates unchanged.

No new violations; Complexity Tracking stays empty.

## Project Structure

### Documentation (this feature)

```text
specs/003-designer-edit-surface/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — D1..D8 decisions (render reuse, public API, edit/undo, perf, tunables, persistence)
├── data-model.md        # Phase 1 — edit-state entities + additive domain helpers + state transitions
├── quickstart.md        # Phase 1 — run/drive the designer; open/save; merge gates
├── contracts/
│   └── designer-edit-api.md   # Phase 1 — new public surface (controller, codec, model) + contract tests
├── checklists/
│   └── requirements.md  # (existing)
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
jet-print/                                   # workspace root (unchanged structure)
├── packages/
│   └── jet_print/                           # THE LIBRARY (the product)
│       ├── CHANGELOG.md                     # updated for this feature
│       ├── lib/
│       │   ├── jet_print.dart               # + export controller, JetReportFormat, and the
│       │   │                                #   ReportTemplate-reachable model graph (contracts §1)
│       │   └── src/
│       │       ├── domain/                  # additive helpers only (stays UI-free)
│       │       │   ├── report_element.dart         # + withBounds(JetRect) (abstract)
│       │       │   ├── elements/text_element.dart  # + copyWith; siblings implement withBounds
│       │       │   ├── elements/{shape,image,barcode}_element.dart  # implement withBounds
│       │       │   ├── report_band.dart            # + copyWith
│       │       │   ├── report_template.dart        # + copyWith
│       │       │   └── serialization/
│       │       │       └── report_format.dart      # NEW — public JetReportFormat facade
│       │       ├── rendering/               # UNCHANGED (reused: renderers, FrameBuilder, CanvasPainter)
│       │       └── designer/
│       │           ├── jet_report_designer.dart    # MODIFIED — optional controller/initialReport/
│       │           │                               #   onSave/onOpen; provides controller via InheritedNotifier;
│       │           │                               #   owns canvas focus + shortcuts
│       │           ├── controller/                 # NEW — edit-state seam
│       │           │   ├── jet_report_designer_controller.dart   # public ChangeNotifier
│       │           │   ├── designer_document.dart               # (template, selection) snapshot
│       │           │   ├── selection.dart
│       │           │   ├── edit_history.dart
│       │           │   ├── clipboard.dart
│       │           │   ├── element_id_factory.dart
│       │           │   ├── edit_command.dart
│       │           │   └── commands/                            # create/move/resize/setGeometry/
│       │           │       └── *.dart                           #   setText/delete/reorder/clipboard/align/distribute/nudge
│       │           ├── canvas/                     # NEW — interactive surface
│       │           │   ├── design_canvas.dart                  # gestures + CustomPaint host
│       │           │   ├── design_time_layout.dart             # template -> band/element page rects
│       │           │   ├── design_time_frame.dart              # template -> PageFrame via ElementRenderer.emit (reuse)
│       │           │   ├── frame_custom_painter.dart           # CustomPainter wrapping CanvasPainter; caches ui.Picture
│       │           │   ├── canvas_view_transform.dart          # zoom/pan; page<->screen
│       │           │   ├── hit_test.dart                       # point -> element (z-order); handle hit
│       │           │   ├── snapping.dart                       # grid/sibling/band/page snap + guides
│       │           │   ├── selection_overlay.dart              # handles, marquee, guides, drag ghosts, drop hint
│       │           │   ├── inline_text_editor.dart             # double-click text edit overlay
│       │           │   └── design_tunables.dart                # D7 constants (grid/snap/nudge/defaults/zoom)
│       │           ├── interaction/
│       │           │   ├── canvas_shortcuts.dart               # Shortcuts/Actions scoped to canvas focus
│       │           │   └── toolbox_drag.dart                   # Draggable<DesignerToolType> + DragTarget
│       │           ├── layout/
│       │           │   ├── designer_surface.dart   # MODIFIED — hosts DesignCanvas (replaces static page)
│       │           │   ├── designer_toolbox.dart   # MODIFIED — entries become Draggable + click-to-place
│       │           │   ├── designer_top_bar.dart   # MODIFIED — wire undo/redo/zoom/grid/snap/save/open to controller
│       │           │   ├── region_chrome.dart      # reused (TreeBranch, SectionLabel, RegionEmptyHint)
│       │           │   └── panels/
│       │           │       ├── outline_panel.dart     # MODIFIED — model-driven tree + selection sync
│       │           │       ├── properties_panel.dart  # MODIFIED — model-driven geometry + text editing
│       │           │       └── data_source_panel.dart # UNCHANGED (Out of Scope)
│       │           └── l10n/
│       │               ├── jet_print_en.arb        # + new affordance/menu/tooltip/a11y keys (template)
│       │               ├── jet_print_de.arb        # + German
│       │               ├── jet_print_tr.arb        # + Turkish
│       │               └── jet_print_localizations*.dart  # regenerated via flutter gen-l10n
│       └── test/
│           ├── public_api_test.dart         # MODIFIED — reference controller/codec/model graph
│           ├── encapsulation_test.dart      # UNCHANGED — still forbids src/ imports
│           ├── domain/                       # + withBounds/copyWith tests; report_format round-trip
│           └── designer/
│               ├── support/designer_harness.dart   # + canvas keys/helpers (pump with a controller)
│               ├── controller/                      # NEW — controller/command/history unit tests
│               ├── canvas/                          # NEW — drop/select/move/resize/marquee/snap/zoom/hit-test
│               ├── interaction/                     # NEW — keyboard (focus-scoped), clipboard, z-order
│               ├── panels/                          # NEW/MODIFIED — outline+properties sync & geometry edit
│               ├── perf/                            # NEW — 200-element drag smoke (SC-007)
│               └── goldens/                         # + design-surface light/dark (shared-render fidelity)
└── apps/
    └── jet_print_playground/                     # PLAYGROUND APP (consumer; macOS)
        ├── pubspec.yaml                      # + file_selector (consumer-only; open/save)
        ├── lib/main.dart                     # MODIFIED — own a controller; wire onSave/onOpen via JetReportFormat
        └── test/app_consumes_library_test.dart  # MODIFIED — still one designer; exercises a basic edit/save path
```

**Structure Decision**: Keep the established Dart pub workspace monorepo. New editing logic lives
entirely in the library's **designer** seam, split into three private clusters —
`controller/` (state + commands + history), `canvas/` (interactive surface + design-time render
reuse), and `interaction/` (keyboard + toolbox DnD) — composed by the existing
`JetReportDesigner` shell. The **domain** seam gets only additive value-copy helpers and a new
public `JetReportFormat` facade; **rendering** is reused untouched. The public entry point gains
exactly the symbols in [contracts/designer-edit-api.md](contracts/designer-edit-api.md) §1;
everything else stays private. The playground app remains a pure consumer that imports only
`package:jet_print/jet_print.dart` and supplies its own file I/O.

## Complexity Tracking

> No entries. The Constitution Check passed with no unjustified violations. The one significant
> structural move — exposing the report model + `JetReportFormat` serialization — is **required by
> the spec** (FR-003 in-memory model; FR-022 open/save via the existing serialization) and
> **anticipated by the constitution** (Principle I: the library is the product; Principle V: the
> serialized format is a user-owned public contract), so it is justified scope, not incidental
> complexity. The sole new dependency (`file_selector`) is confined to the playground app, leaving the
> published package's dependency surface unchanged.

---

## Phase Status

- **Phase 0 — Research**: ✅ complete → [research.md](research.md) (D1–D8; no `NEEDS CLARIFICATION`
  remaining).
- **Phase 1 — Design & Contracts**: ✅ complete → [data-model.md](data-model.md),
  [contracts/designer-edit-api.md](contracts/designer-edit-api.md), [quickstart.md](quickstart.md);
  agent context (`CLAUDE.md`) updated to point here.
- **Phase 2 — Tasks**: ⏳ not started — produced by `/speckit.tasks` (NOT this command).
