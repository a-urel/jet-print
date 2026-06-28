# First-Class "Add" for the Five Singleton Bands — Design

**Date:** 2026-06-28
**Status:** Design approved; pending spec review → implementation plan.

## Problem

The report-level bands — report header (`ReportBody.title`), report footer
(`ReportBody.summary`), page header / page footer (`PageFurniture.pageHeader` /
`pageFooter`), and no-data (`ReportBody.noData`) — all exist in the engine and
render correctly. But the designer offers no way to *create* them directly. The
outline's "+" affordances add only detail bands, nested lists, and group
header/footer bands. The five singleton-slot bands are reachable **only by
retyping an existing band** into an empty slot
(`outline_panel.dart` `_retypeTargets`, `controller.retypeBand`).

Authors don't discover the retype path, so they place report-level content into
the one report-wide band they *can* easily produce — the page header — and get
content that repeats on every page. The sales-ledger playground demo does
exactly this: its "Sales Ledger" title lives in `PageFurniture.pageHeader`
(`apps/jet_print_playground/lib/ledger_sample.dart:44-102`) and therefore
reprints on every page instead of once at the top.

**This is a discoverability and authoring gap, not a missing model.** No new
band type is needed: `BandType.title` and `BandType.summary` already *are*
report header and report footer (the same names JasperReports uses), and they
live in dedicated structural slots that the fill engine prints once at the start
(`report_filler.dart:539`) and once at the end (`report_filler.dart:615`).

## Goal

Make all five singleton-slot bands first-class "Add" actions in the designer,
relabel `title`/`summary` to the names authors expect ("Report Header" /
"Report Footer"), and fix the ledger demo to use the correct slot.

## Non-Goals

- No change to the `BandType` enum, the domain model, or serialization.
- No change to the render/fill/layout engine.
- No change to the retype path (it stays, unchanged, as a secondary route).
- No new band kinds, no schema version bump.

## Scope Summary

Designer authoring + user-facing labels + one playground demo correction.

## Architecture

The change spans three layers, all already established:

1. **Controller (command).** A new undoable command that creates an empty band
   in an empty singleton slot — the additive sibling of the existing
   `retypeBand` (which only *relocates* an existing band).
2. **Outline panel (UI).** A report-level "+" menu on the existing Report root
   row, parallel to the per-scope "+" menu, listing only the currently-empty
   singleton slots.
3. **Localization (labels).** Two ARB value changes, single-sourced through the
   existing `bandTypeLabel`.

Plus a data-only fix to one playground demo definition.

## Components

### Component 1 — `addSingletonBand(BandType type)` on the controller

New method on `JetReportDesignerController`, modeled directly on `retypeBand`
(`jet_report_designer_controller.dart:1106`).

- **Guards (no-op when violated):**
  - `isSingletonSlotType(type)` is false → no-op (only the five singleton slots
    are valid targets).
  - `bandInSlot(definition, type) != null` → no-op (slot already occupied).
- **Action:** construct `Band(id: <newly generated id>, type: type,
  height: _defaultBandHeight(type), elements: <empty>)`, then commit
  `setSlotBand(definition, type, band)` as a single `DefinitionEditCommand`
  (one undoable step), with `selection: Selection.band(newId)` so the new band
  is selected and its Properties panel opens.
- Reuses the existing `_defaultBandHeight(type)` helper
  (`jet_report_designer_controller.dart:1121`): title/summary = 32, noData = 40,
  others = 24.
- Id generation follows the same approach `addDetailBand` uses (the
  implementation plan will confirm the exact id-minting helper).

### Component 2 — Report-root "+" menu in the outline

The Report root branch row (`outline_panel.dart:131`) currently has no
`actions:`. Add a `_TypeMenu` "+" affordance there (icon `LucideIcons.plus`),
parallel to the per-scope `_addMenu` (`outline_panel.dart:258`).

- Menu options: one entry per singleton slot type, in a stable, sensible order
  (report header, page header, page footer, report footer, no-data).
- Each entry is **omitted when its slot is occupied**
  (`bandInSlot(definition, type) != null`) — so the menu only ever offers slots
  you can actually fill. (Omit rather than disable, matching how the scope menu
  omits an already-present group header/footer.)
- Entry label = `bandTypeLabel(type, l10n)` (already localized; the same caption
  the retype menu and canvas badges use).
- `onPick` → `controller.addSingletonBand(type)`.
- Stable `ValueKey`s under `jet_print.designer.outline.report.add...` for tests.

The retype menu and `_retypeTargets` whitelist are left unchanged.

### Component 3 — Labels

`bandTypeLabel` (`designer/l10n/band_type_label.dart`) is the single source for
band captions, used by canvas band badges, the outline, the retype menu, and the
new add menu. Relabel two captions in the ARB files (and their generated
delegate), for every supported locale:

- `bandTypeTitle`: "Title" → **"Report Header"** (de/tr variants updated to
  match).
- `bandTypeSummary`: "Summary" → **"Report Footer"** (de/tr variants updated).

No new l10n keys are introduced — only value changes. Page Header, Page Footer,
and No Data captions are already correct.

**ARB sync discipline:** edit the `.arb` source files and regenerate the
localization delegate; do not hand-edit generated Dart (a known trap from the
chart spec, where keys existed only in generated Dart and were missing from the
ARBs).

### Component 4 — Ledger demo fix

In `apps/jet_print_playground/lib/ledger_sample.dart`, move the `'Sales Ledger'`
`TextElement` out of `PageFurniture.pageHeader` and into `ReportBody.title`
(creating the title band if absent). Keep the column-heading `TextElement`s in
`pageHeader` — those correctly repeat per page. Adjust y-offsets so the title
band and the page-header band each lay out cleanly on their own.

Result: the title prints once at the top of the report; column headings repeat
on every page. This both fixes the demo and showcases the newly-discoverable
report-header authoring.

## Data Flow

Author clicks the Report root "+" → picks "Report Header" → controller
`addSingletonBand(BandType.title)` commits an empty title band into
`body.title` and selects it → outline shows the new band row, canvas shows the
once-at-top band, Properties panel targets it → author drops elements in. No
fill/render code path changes; the engine already prints `body.title` once.

## Error Handling / Edge Cases

- Adding into an occupied slot: command is a no-op (and the menu entry isn't
  even offered). Belt and suspenders.
- Undo: a single `DefinitionEditCommand` step removes the added band and
  restores prior selection, like every other outline edit.
- Removing a singleton band (existing trash affordance) frees its slot, so its
  add entry reappears — no special handling needed.

## Testing

- **Controller unit tests** (`test/designer/controller/...`): for each of the
  five types, adding into an empty slot creates a band of the right type with
  the default height and selects it; adding into an occupied slot is a no-op;
  adding a non-singleton type is a no-op; undo restores the prior definition and
  selection.
- **Outline widget test**: the report "+" menu lists exactly the empty singleton
  slots; an occupied slot's entry is absent; tapping an entry adds the band and
  selects it (assert via the stable `ValueKey`s).
- **Label test**: `bandTypeLabel(BandType.title)` / `bandTypeSummary` return the
  new captions for each locale.
- **Intentional golden churn** (regenerate deliberately, document why; do not
  treat as regressions):
  - Ledger demo goldens — the title moves from page header to report title.
  - Canvas band-badge goldens for title/summary — the relabel changes badge
    text (and per the chart-spec lesson, text changes can drift the Skia
    glyph-cache, so adjacent canvas goldens may need regen too).

## Constitution Alignment

- **Library-first / clean API:** additive controller method; no new public
  surface beyond the designer.
- **Layered architecture:** domain/render untouched; the change is confined to
  the designer controller + outline panel + l10n.
- **Test-First:** every new behavior lands Red→Green.
- **Rendering fidelity:** no render-path change; the only golden changes are the
  intentional demo move and the relabel, both explained.
- **Serialization:** no model/codec change; no schema bump.

## Open Questions

None. Design approved 2026-06-28.
