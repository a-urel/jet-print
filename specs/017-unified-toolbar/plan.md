# Implementation Plan: Unified Context-Switching Toolbar

**Branch**: `017-unified-toolbar` | **Date**: 2026-06-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/017-unified-toolbar/spec.md`

## Summary

Make the designer and the preview read as **one toolbar that changes by context**. Today they are
two separate bars: the designer's
[`DesignerTopBar`](../../packages/jet_print/lib/src/designer/layout/designer_top_bar.dart#L23)
(title + history/clipboard/zoom/view-toggle/arrange groups + Open/Save/Preview/Export) and the
preview's toolbar inside
[`JetReportPreview`](../../packages/jet_print/lib/src/designer/preview/jet_report_preview.dart#L56)
(title + export/print + zoom + page-nav). Both are already **52 px tall** and styled to match — the
visual continuity is half-built.

This feature finishes it with three moves, all in the **designer** layer:

1. **A shared toolbar shell** — a new private widget (`unified_top_bar.dart`) that lays out the
   three regions every mode shares: **left** (file icon + report name + inline-rename affordance),
   **center** (a two-segment **Designer | Preview** switch with the active mode highlighted), and a
   **right** slot the caller fills with mode-specific actions. `DesignerTopBar` and the preview
   toolbar both compose this shell, so the left + center regions are positionally identical across
   modes (FR-001, SC-003) and only the right slot differs (FR-011, US3).

2. **The mode switch wired to existing callbacks** — per the clarification *the host owns mode and
   performs the switch; the toolbar emits a switch request*. Those requests already exist:
   selecting **Preview** from designer fires
   [`onPreviewRequested`](../../packages/jet_print/lib/src/designer/jet_report_designer.dart#L97);
   selecting **Designer** from preview fires
   [`onBack`](../../packages/jet_print/lib/src/designer/preview/jet_report_preview.dart#L78). The
   playground already performs the swap (a `Navigator` push / `pop`). The switch renders in both
   modes; the inactive segment is enabled only when its callback is wired (mirroring how the Preview
   action disables when `onPreviewRequested` is null) (FR-002, FR-003, FR-004, US1).

3. **Inline rename in both modes** — the name field already lives on the model
   ([`ReportTemplate.name`](../../packages/jet_print/lib/src/domain/report_template.dart#L25),
   always serialized, `schemaVersion` unchanged). We add **one** undoable controller op,
   `rename(String)` (a `SetTemplateNameCommand` through the existing
   [`_commit`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L937)
   path), used directly by the designer toolbar via `DesignerScope`. Preview has no controller (it
   holds a `RenderedReport` whose `title` carries the name), so it gains **one** callback,
   `onRename`, that the host wires to `controller.rename`; the preview shell shows the freshly typed
   name locally for the immediate-feedback requirement. Escape cancels; blur commits a non-empty
   name; confirming empty/whitespace shows the placeholder (FR-006–FR-010, US2).

Net public surface: **two additive symbols** — `JetReportDesignerController.rename(String)` and
`JetReportPreview.onRename` — exactly the minimal-surface idiom 016 used for `canCopy`/`canPaste`.
The mode-switch widget, the shell, and the internal mode enum stay private under `src/`. Nothing
touches the render pipeline or serialization, so report goldens and saved files stay byte-identical.

See [research.md](research.md) for the grounded decisions (shell extraction, reuse of
`onPreviewRequested`/`onBack` as switch events, the `rename` command, preview's local-name display,
empty-name → placeholder, l10n keys, zero render/serialization impact), [data-model.md](data-model.md)
for the entities (one new command, the view-only `WorkspaceMode`, the rename truth table),
[contracts/unified-toolbar.md](contracts/unified-toolbar.md) for the behavioral contracts + test
groups, and [quickstart.md](quickstart.md) for the host wiring.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only — `shadcn_ui ^0.54.0` (`ShadIconButton`, `ShadTooltip`,
`ShadButton`/segmented styling, `ShadInput` for inline edit), `flutter` (`Focus`/`FocusNode`,
`TextEditingController`, `Semantics`, `LayoutBuilder`). The designer top bar and preview toolbar
already use these. **No new dependencies.**
**Storage**: None new. `ReportTemplate.name` already exists and is always encoded
(`report_codec.dart`); `kReportSchemaVersion` stays **1**, no migration. Rename funnels through the
existing in-memory command/undo history. Workspace mode is host-owned ephemeral view state.
**Testing**: `flutter test packages/jet_print` (from repo root). Unit — `rename()` updates the name,
is a single undoable step, notifies once, and round-trips through the codec; empty/whitespace name is
stored as `''`. Widget — designer toolbar shows the mode switch (Designer active) + rename affordance,
Preview segment fires `onPreviewRequested`, inline rename commits via Enter/blur and cancels via
Escape (`top_bar_test.dart`); preview toolbar shows the switch (Preview active), Designer segment
fires `onBack`, rename fires `onRename` and updates the shown name (`jet_report_preview_test.dart`);
shared-shell region parity + responsive collapse + a11y over en/de/tr (`unified_toolbar_test.dart`).
Regression — existing top-bar/preview/codec/golden suites stay green; `public_api_test.dart` updated
for the two new symbols.
**Target Platform**: Designer + preview UI (Flutter desktop/web). Reference environment: macOS
desktop playground (`apps/jet_print_playground`).
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` + consumer app
`apps/jet_print_playground`.
**Performance Goals**: No new budget. The shell reads the controller through the existing
`DesignerScope` `InheritedNotifier`; rename is one `_commit`. Switching modes is the existing
host swap (no preview re-render added by this feature). The cached element picture
(`FrameCustomPainter`) and the render pipeline are untouched.
**Constraints**: WYSIWYG (IV) — chrome only, no render-path change, so canvas/preview/export/print
stay identical and **no report golden moves**. Layer boundary (II) — all code in the **designer**
seam (`controller`, `layout`, `preview`, `l10n`); rename uses `ReportTemplate.copyWith`, adding no
domain→UI dependency. Minimal public surface (I) — exactly two new symbols; the shell + mode switch
+ mode enum stay private. FR-001/SC-003 — left + center regions are one shared widget, so they
**cannot** drift between modes.
**Scale/Scope**: 1 new controller op (`rename`) + 1 new command class · 1 shared shell widget + 1
segmented mode-switch widget · `DesignerTopBar` and the preview toolbar refactored to compose the
shell · 1 new preview callback (`onRename`) · ~4 new ARB keys × 3 locales · the test matrix above ·
3 user stories (P1 switch, P2 rename, P3 mode-specific actions).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | Exactly **two** new public symbols — `JetReportDesignerController.rename(String)` (undoable, mirrors the existing mutator idiom) and `JetReportPreview.onRename` (a `ValueChanged<String>?` callback, the host-wired idiom `onExportPdf`/`onPrint` already use). The shared shell, the segmented mode switch, and the `WorkspaceMode` enum all stay **private** under `src/`. The mode-switch *events* reuse the already-public `onPreviewRequested`/`onBack`. `public_api_test` updated to record the two additions. **Zero new host wiring for the designer** (rename is internal via `DesignerScope`); preview rename is one optional callback. |
| II | Layered & Extensible Architecture | ✅ PASS | Everything lives in the **designer** seam (`controller/commands`, `layout`, `preview`, `l10n`). `rename` is a pure `SetTemplateNameCommand` applying `ReportTemplate.copyWith(name:)` — the domain stays free of UI/rendering. The shell composes existing widgets; no rendering import is added. `layer_boundaries_test` stays green. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green→refactor. The load-bearing behavior — `rename()` is a single undoable, notifying step that survives a codec round-trip — is pinned by a **failing** controller unit test first. The mode switch firing the right callback per mode, inline-edit commit/cancel/blur rules, empty→placeholder, and region parity are each driven by widget tests before the widgets exist. No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | This is **toolbar chrome only** — no element appearance, no pagination, nothing through `paintFrame`/`FrameCustomPainter`. Preview still paints each page through the shared pipeline unchanged. Therefore canvas/preview/print stay identical and **no existing report golden changes** (SC-003 region parity is asserted by widget/golden of the *toolbar*, not the report). |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | `ReportTemplate.name` already exists and is already always serialized; this feature only *edits* it. No new field, no codec change, `kReportSchemaVersion` stays **1**, no migration. Old and new templates load and serialize byte-identically; the codec round-trip test proves a renamed template is lossless. |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on `rename` (notes single-undo-step + empty→placeholder semantics) and `onRename` (host wires to `controller.rename`); `CHANGELOG.md` updated (unified toolbar + inline rename + mode switch). New strings localized in all three ARBs (FR-013). The playground demonstrates the round-trip (rename in designer, switch to preview, see the new name). Zero analyzer warnings; `dart format` clean. |

**Result: PASS — no violations.** Two items recorded in *Complexity Tracking* for reviewer
visibility: (a) the mode-switch *events* deliberately reuse `onPreviewRequested`/`onBack` rather than
introducing a new `mode`/`onModeChanged` API (smaller surface, host already owns the swap); (b)
preview keeps a small local "displayed name" so a rename shows immediately even though its
`RenderedReport.title` is immutable.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md), [contracts/unified-toolbar.md](contracts/unified-toolbar.md),
and [quickstart.md](quickstart.md): still **PASS**. Public surface stayed at exactly two symbols;
the shell/switch/enum stayed private; the render path was not forked; no model/codec/schema change.
The shared shell guarantees left+center parity (FR-001), and the two modes feed identical name +
switch state through one widget so they cannot diverge. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/017-unified-toolbar/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — shell extraction; reuse onPreviewRequested/onBack; rename command; preview local-name; empty→placeholder; l10n; zero render/serialization impact
├── data-model.md        # Phase 1 — SetTemplateNameCommand; view-only WorkspaceMode; rename/commit truth table; NO domain/serialization change
├── quickstart.md        # Phase 1 — host wiring (designer: zero; preview: onRename); the rename→switch→see-name round-trip
├── contracts/
│   └── unified-toolbar.md  # Phase 1 — behavioral contracts (shell parity, mode switch, inline rename, mode-specific actions, invariants) + test groups
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/
│   ├── jet_print.dart                                   # CHANGE: re-export already covers controller + JetReportPreview;
│   │                                                    #         no new export needed (rename is a method; onRename is a field)
│   └── src/designer/
│       ├── controller/
│       │   ├── jet_report_designer_controller.dart      # CHANGE: add `void rename(String name)` → _commit(SetTemplateNameCommand)
│       │   └── commands/
│       │       └── set_template_name_command.dart       # NEW: EditCommand applying template.copyWith(name:)
│       ├── layout/
│       │   ├── unified_top_bar.dart                     # NEW (private): shared shell — left (name + inline rename),
│       │   │                                            #                center (mode switch), right (actions slot)
│       │   ├── workspace_mode_switch.dart               # NEW (private): two-segment Designer|Preview control + WorkspaceMode enum
│       │   └── designer_top_bar.dart                    # CHANGE: compose unified shell; pass designer action groups as the right slot;
│       │   │                                            #         mode=Designer, onSwitchToPreview=onPreview; wire rename → controller.rename
│       ├── preview/
│       │   └── jet_report_preview.dart                  # CHANGE: compose unified shell; mode=Preview, onSwitchToDesigner=onBack;
│       │   │                                            #         add `final ValueChanged<String>? onRename`; local displayed-name state
│       └── l10n/
│           ├── jet_print_en.arb                         # CHANGE: + modeDesigner, modePreview, actionRenameTooltip, renameFieldLabel (+@desc)
│           ├── jet_print_de.arb                         # CHANGE: + same keys, German
│           └── jet_print_tr.arb                         # CHANGE: + same keys, Turkish
│
└── test/
    ├── designer/controller/
    │   └── rename_test.dart                             # NEW: rename() updates name, single undo step, notifies once, codec round-trip; empty→''
    ├── designer/top_bar_test.dart                       # EXTEND: mode switch present (Designer active); Preview segment → onPreviewRequested;
    │                                                    #         rename affordance; Enter/blur commit, Escape cancel; designer-only actions present
    ├── designer/preview/jet_report_preview_test.dart    # EXTEND: mode switch present (Preview active); Designer segment → onBack;
    │                                                    #         rename → onRename + shown name updates; preview-only actions present
    ├── designer/unified_toolbar_test.dart               # NEW: left+center region parity across modes (SC-003); responsive collapse keeps name+switch; a11y/l10n en/de/tr
    └── public_api_test.dart                             # UPDATE: record rename() + JetReportPreview.onRename; no other surface change
```

**Structure Decision**: Existing workspace monorepo, no new top-level structure. The shared shell
(`unified_top_bar.dart`) and the mode switch (`workspace_mode_switch.dart`) are new **private**
widgets in the designer `layout/` directory beside `designer_top_bar.dart`; both `DesignerTopBar` and
the preview toolbar are refactored to *compose* the shell rather than each owning a bespoke left/
center region. The only "state of record" stays the controller (the single `InheritedNotifier`),
which gains one mutator (`rename`) built from one new command through the existing `_commit` path;
workspace mode remains host-owned and is reflected into each toolbar as a value. Preview, having no
controller, gains one optional callback (`onRename`) and a small local displayed-name for immediate
feedback.

## Complexity Tracking

> No Constitution **violations** to justify. Two tracked items for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Mode-switch events reuse `onPreviewRequested` / `onBack` instead of a new `mode` + `onModeChanged` API | The clarification fixes mode ownership in the **host**, which already performs the swap (the playground pushes/pops a preview route). Those two callbacks already *are* "switch to Preview" / "switch to Designer" requests. Introducing a parallel mode API would duplicate the seam and enlarge the public surface for no behavioral gain (Constitution I). | The center switch renders in both modes; the inactive segment enables only when its callback is wired (same pattern as the Preview action disabling on a null `onPreviewRequested`). Pinned by widget tests asserting which callback fires per mode. |
| Preview keeps a local "displayed name" override | FR-008 requires a rename to **immediately** reflect in the shown name, but `RenderedReport.title` is immutable and preview holds no controller. The host re-renders on its own cadence; the local override bridges the gap between "typed now" and "host persisted/re-rendered". | Seeded from `report.title`; updated on commit; `onRename` still fires so the host owns persistence. Pinned by a widget test: rename in preview updates the visible title and calls `onRename` with the new value. |
