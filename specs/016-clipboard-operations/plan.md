# Implementation Plan: Clipboard Operations in the Designer UI

**Branch**: `016-clipboard-operations` | **Date**: 2026-06-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/016-clipboard-operations/spec.md`

## Summary

Make the designer's already-existing cut/copy/paste **discoverable and operable without the
keyboard** by adding two UI surfaces. The clipboard backend is complete and unchanged: the
in-memory [`Clipboard`](../../packages/jet_print/lib/src/designer/controller/clipboard.dart), the
controller [`copy()/cut()/paste()/duplicate()/delete()`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L735)
(fresh-id, paste offset, band-clamp, single-undo-step), and the
[keyboard shortcuts](../../packages/jet_print/lib/src/designer/interaction/canvas_shortcuts.dart)
already work. This feature adds *invocation points*, not clipboard logic (FR-003).

Three things change, all in the **designer** layer:

1. **Toolbar group** — a fenced Cut / Copy / Paste cluster of
   [`_IconButton`](../../packages/jet_print/lib/src/designer/layout/designer_top_bar.dart#L411)s,
   identical in construction to Undo/Redo, placed right after the History group (US1, P1).

2. **Canvas context menu** — net-new (the canvas has **no** right-click menu today). A
   `ShadContextMenuRegion` (already in `shadcn_ui ^0.54.0`) wrapping the canvas, with the same
   [`ShadContextMenuItem`](../../packages/jet_print/lib/src/designer/layout/designer_top_bar.dart#L304)
   widgets the Arrange menu uses: Cut, Copy, Paste, Duplicate, Delete. An `onSecondaryTapDown`
   handler resolves selection via the existing
   [`hitTestElement`](../../packages/jet_print/lib/src/designer/canvas/hit_testing.dart#L23) *before*
   the menu opens (FR-010) (US2, P2).

3. **The one backend gap + localization/a11y polish** — `copy()` does **not** currently
   `notifyListeners()`, so a Paste control would not re-enable after a Copy. Because the UI rebuilds
   through [`DesignerScope`](../../packages/jet_print/lib/src/designer/designer_scope.dart#L11) (an
   `InheritedNotifier`), the fix is to notify from `copy()` and expose two getters (`canCopy`,
   `canPaste`) mirroring `canUndo`/`canRedo`. Localized labels (en/de/tr) with platform shortcut
   hints and `Semantics` names complete it (US3, P3).

Nothing routes through serialization or the render pipeline, so saved files and preview/export/print
output stay **byte-for-byte unchanged** and all goldens remain green by construction.

See [research.md](research.md) for the eight grounded decisions (the `copy()` notify, the getters,
toolbar placement, `ShadContextMenuRegion`, FR-010 hit-testing, shortcut-hint composition, l10n keys,
zero model/render impact), [data-model.md](data-model.md) for the (view-only) entities + enablement
truth table, [contracts/clipboard-ui.md](contracts/clipboard-ui.md) for the five behavioral
contracts + test groups, and [quickstart.md](quickstart.md) for the (zero) host wiring.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only — `shadcn_ui ^0.54.0` (`ShadContextMenuRegion`,
`ShadContextMenuItem`, `ShadIconButton`, `ShadTooltip`, already used), `flutter` (`GestureDetector`
secondary-tap, `Semantics`). The pinned shadcn_ui version ships `ShadContextMenuRegion` (verified in
`~/.pub-cache/.../shadcn_ui-0.54.0/lib/src/components/context_menu.dart`). **No new dependencies.**
**Storage**: None. No report-model field, no codec change, `schemaVersion` untouched. Clipboard is
session-scoped in-memory view state; selection is in-memory controller state. Nothing persisted.
**Testing**: `flutter test packages/jet_print` (from repo root). Unit — controller reactivity
(`copy()` notifies once, no undo entry; `canCopy`/`canPaste` truth table; cut empties selection).
Widget — top-bar group presence + enablement + reactive Paste-after-Copy + mouse-only copy/paste +
cut→undo (`top_bar_test.dart`); context menu open/select/dismiss + FR-010 selection rules + duplicate
/delete single-step (`context_menu_test.dart`); localization + a11y over en/de/tr
(`clipboard_l10n_test.dart`). Regression — `keyboard_clipboard_test.dart`, `bulk_commands_test.dart`,
codec + golden suites stay green; `public_api_test.dart` updated for the two getters.
**Target Platform**: Designer UI (Flutter desktop/web canvas). Shortcut-glyph selection (⌘ vs Ctrl+)
keys off `defaultTargetPlatform`. Reference environment: macOS desktop playground.
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` + consumer app
`apps/jet_print_playground`.
**Performance Goals**: No new budget. Both surfaces read O(1) getters and rebuild via the existing
`DesignerScope` InheritedNotifier path (same mechanism Undo/Redo already use). The context menu is
built lazily on secondary-tap; `hitTestElement` is the same O(elements) scan the primary tap already
runs. The cached element picture (`FrameCustomPainter`) is untouched.
**Constraints**: WYSIWYG (IV) — no render-path change, so canvas/preview/export stay identical and no
golden moves. Layer boundary (II) — all code in the **designer** seam; no domain/render imports
added. Minimal public surface (I) — exactly two new getters (`canCopy`, `canPaste`), mirroring the
existing `can*` idiom; the menu/handlers stay private under `src/`. FR-003 — both surfaces call the
existing controller ops; no second clipboard. FR-012 — toolbar and menu read the same two
predicates, so they cannot diverge.
**Scale/Scope**: 1 behavior change (`copy()` notifies) + 2 getters · 3 toolbar `_IconButton`s + 1
divider · 1 `ShadContextMenuRegion` + 5 menu items + 1 `onSecondaryTapDown` selection handler · 5 new
ARB keys × 3 locales · the test matrix above. 3 user stories (P1, P2, P3).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | Exactly **two** new public symbols — `canCopy`, `canPaste` getters on the already-public controller, mirroring `canUndo`/`canRedo`. `canPaste` is *required* (clipboard is private); `canCopy` keeps both surfaces reading one predicate (FR-012). Toolbar widgets, the context menu, and the secondary-tap handler all stay private under `src/`. `public_api_test` updated to record the two getters — a reviewed, additive surface change. **Zero host wiring** — the surfaces appear inside `JetReportDesigner` automatically. |
| II | Layered & Extensible Architecture | ✅ PASS | Everything lives in the **designer** seam (`controller`, `layout/designer_top_bar.dart`, `canvas/design_canvas.dart`, `l10n`). No domain/rendering imports are added. The menu reuses existing `ShadContextMenuItem`; selection reuses the existing `hitTestElement` helper. `layer_boundaries_test` stays green. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green→refactor. The genuinely-load-bearing behavior — that `copy()` notifies so Paste re-enables — is pinned by a **failing** controller unit test first (it fails today), then the notify is added. Enablement (truth table), the FR-010 selection rules, dismissal, and localization are each driven by tests before the widgets. No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | This feature adds **invocation surfaces only** — no element appearance, no preview/export, nothing through `FrameCustomPainter`. Therefore canvas/preview/print stay identical and **no existing golden changes** (SC-006). Paste's visual result (offset copy) is the existing, already-golden behavior. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | Zero serialization impact: no model field, no codec change, `schemaVersion` untouched, no migration (FR-016). Clipboard/selection are ephemeral view state. Old and new templates load and serialize byte-identically. |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on the two new getters and the updated `copy()` (notes the notify-without-undo intent); `CHANGELOG.md` updated (toolbar clipboard group + canvas context menu). New strings localized in all three ARBs (FR-013). Playground invoice demonstrates both surfaces. Zero analyzer warnings; `dart format` clean. |

**Result: PASS — no violations.** One item is recorded in *Complexity Tracking* for reviewer
visibility: `copy()` gains a `notifyListeners()` **without** creating an undo entry — an intentional
split between "notify the UI" and "commit to history" (research D1).

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md), [contracts/clipboard-ui.md](contracts/clipboard-ui.md),
and [quickstart.md](quickstart.md): still **PASS**. Public surface stayed at exactly two getters; all
new code stayed in the designer seam reusing existing widgets/helpers; the render path was not
forked; no model/codec/schema change. The two surfaces read identical predicates (FR-012) and call
the existing controller ops (FR-003). No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/016-clipboard-operations/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — copy() notify, getters, toolbar placement, ShadContextMenuRegion, FR-010 hit-test, shortcut hints, l10n, zero model/render impact
├── data-model.md        # Phase 1 — view-only entities, enablement truth table, additive controller surface; NO domain/serialization change
├── quickstart.md        # Phase 1 — designer UX + (zero) host wiring
├── contracts/
│   └── clipboard-ui.md  # Phase 1 — five behavioral contracts (plumbing, toolbar, context menu, l10n/a11y, invariants) + test groups
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/src/designer/
│   ├── controller/
│   │   ├── jet_report_designer_controller.dart   # CHANGE: copy() → notifyListeners() (no undo entry);
│   │   │                                          #         add `bool get canCopy`, `bool get canPaste`
│   │   └── clipboard.dart                         # (unchanged — Clipboard.isEmpty read via canPaste)
│   ├── layout/
│   │   └── designer_top_bar.dart                  # CHANGE: add Cut/Copy/Paste _IconButton group (after History);
│   │   │                                          #         tooltips = localized label + platform shortcut hint
│   ├── canvas/
│   │   ├── design_canvas.dart                     # CHANGE: onSecondaryTapDown → hitTestElement + FR-010 selection;
│   │   │                                          #         wrap canvas content in ShadContextMenuRegion (Cut/Copy/Paste/Dup/Delete)
│   │   └── hit_testing.dart                       # (unchanged — reuse hitTestElement for right-click selection)
│   ├── interaction/
│   │   └── canvas_shortcuts.dart                  # (unchanged — keyboard shortcuts keep working, FR-017)
│   └── l10n/
│       ├── jet_print_en.arb                       # CHANGE: + actionCutTooltip/CopyTooltip/PasteTooltip, menuDuplicate, menuDelete (+@desc)
│       ├── jet_print_de.arb                       # CHANGE: + same keys, German
│       └── jet_print_tr.arb                       # CHANGE: + same keys, Turkish
│
└── test/
    ├── designer/controller/clipboard_reactivity_test.dart   # NEW: copy() notifies once + no undo; canCopy/canPaste truth table; cut empties selection
    ├── designer/controller/bulk_commands_test.dart          # VERIFY unchanged: existing cut/copy/paste/duplicate green (FR-017, SC-005)
    ├── designer/top_bar_test.dart                           # EXTEND: clipboard group present; enablement; reactive Paste-after-Copy; mouse-only copy/paste; cut→undo; tooltip+shortcut
    ├── designer/canvas/context_menu_test.dart               # NEW: open/select/dismiss; FR-010 selection rules; duplicate/delete single-step; Paste enablement on empty canvas
    ├── designer/clipboard_l10n_test.dart                    # NEW: en/de/tr labels resolve; Semantics names; platform shortcut glyph
    ├── designer/interaction/keyboard_clipboard_test.dart    # VERIFY unchanged: shortcuts still work (FR-017, SC-005)
    └── public_api_test.dart                                 # UPDATE: record canCopy, canPaste; no other exported surface
```

**Structure Decision**: Existing workspace monorepo, no new top-level structure. The toolbar group
slots into `designer_top_bar.dart` beside the controls it joins (Undo/Redo, reusing `_IconButton`);
the context menu attaches at the canvas gesture layer in `design_canvas.dart`, reusing the
`ShadContextMenuItem` widget the Arrange menu already uses and the `hitTestElement` helper the
primary tap already uses. The only "state of record" is the controller (already the single
`InheritedNotifier`); this feature adds two read-only getters and one missing notify, then composes
existing widgets around them.

## Complexity Tracking

> No Constitution **violations** to justify. One tracked item for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| `copy()` gains `notifyListeners()` but creates **no** undo entry | The toolbar/canvas rebuild only on controller notify (via `DesignerScope`'s `InheritedNotifier`). A Copy changes derived UI state (`canPaste` flips true) but must remain non-undoable (FR-009). So "notify the UI" and "commit to history" are intentionally split — `copy()` notifies without committing, unlike every other mutating op which does both through `_commit`. | Pinned by a unit test asserting one notification **and** `canUndo` unchanged across a Copy (research D1, contract C1). Without this, Paste would silently fail to re-enable after a mouse Copy — the subtlest correctness risk in the feature. |
