# Rename report objects — design

**Date:** 2026-06-26
**Status:** Approved (brainstorm)
**Area:** `packages/jet_print/lib/src/designer/`

## Problem

In the visual designer, every report object (an element such as `TextElement`/
`ShapeElement`, or a band such as Group Header / Detail / Group Footer) is shown
by its `id` — e.g. `grandTotalRule`, `invoiceFooter` — in the Properties panel
header and in the Outline tree. There is no way to change that name from the UI.
Authors want to rename objects to keep a report's structure legible.

## Decision: rename edits the `id` in place

The displayed name **is** the object's `id`. There is no separate human-facing
label field on `ReportElement` or `Band` (only `GroupLevel` has a distinct
`name`). We rename the `id` itself rather than introduce a parallel `name` field.

This is safe and minimal because, per codebase investigation:

- Element/band `id` is **never referenced by string** in expressions
  (`$F{}`/`$V{}`/`$P{}`), data bindings, group/variable references, or published
  totals. Those use schema field names, `GroupLevel.id`, and `ScopeTotal.name`.
- `id` is used **only as an identity key**: selection, hit-testing/lookup,
  copy/paste id generation, undo/redo mutation keys, and serialization.
- Ids are already authored as readable names (`grandTotalRule`,
  `subtotalLabel`), so editing the id matches the existing mental model.

Therefore renaming requires **no domain-model change** — no new field, no codec
changes, no `copyWith` signature growth across element subtypes.

## Scope

Renamable: **every `ReportElement` and every `Band`**, including bands with
structural roles (page footer, etc.). A band's role lives in the separate
`BandType` enum, not in its `id`, so renaming the id never alters the role and
no band id is reserved.

Two entry points, both driving the *same* command so behavior is identical:

1. **Properties panel header** — the name label (`properties_panel.dart` `_Header`,
   currently fed `element.id` at ~line 244) becomes click-to-edit: click (or a
   pencil affordance) swaps it for an inline text field. Enter commits, Esc
   cancels.
2. **Outline tree row** — double-click a row (`outline_panel.dart`, label
   `element.id` at ~line 326, and the band rows) enters inline edit. Enter
   commits, Esc cancels.

## Command

Add a `RenameCommand(targetId, newId)` to the existing undo/redo command stack,
reusing the `updateElement` / band-walker mutation helpers
(`controller/band_walker.dart`, pattern as in `set_text_command.dart`).

Execute:

1. **Validate** (see below). Invalid → command is **not** pushed onto the stack;
   the inline editor stays open showing the error.
2. Rewrite the target's `id` via `copyWith(id: newId)` (works for both elements
   and bands — both expose `id` + `copyWith`).
3. **Re-point controller selection** from `targetId` → `newId` so the renamed
   object stays selected. Clipboard is left untouched.

Undo restores the old `id` and the prior selection; redo re-applies. Snapshot
(before/after definition) style consistent with existing commands.

## Validation

Reuses the rule behind validator invariant **I1** (id uniqueness). On commit,
reject when the proposed `id` is:

- empty or whitespace-only, or
- equal to any **other** existing element *or* band id anywhere in the report
  (global uniqueness, matching I1).

Behavior on invalid: **block + inline error** — the edit field stays open with a
red border and a short message (`id already used` / `name required`). Nothing
commits until valid; Esc cancels and reverts to the old id. A no-change commit
(same id) is a silent no-op (not flagged as a duplicate of itself).

## Testing

- **Command unit tests:** rename element; rename band; duplicate rejected (no
  mutation, no stack push); empty/whitespace rejected; undo restores old id;
  redo re-applies; selection follows the rename; same-id commit is a no-op.
- **Widget tests:** Properties-header inline editor (Enter commits, Esc cancels,
  duplicate shows error and stays open); Outline double-click editor (same).
- **Goldens:** unaffected — `id` is never painted onto the canvas.

## Out of scope

- A separate display `name` field distinct from `id`.
- Bulk/rename-find-replace across multiple objects.
- Renaming non-object identifiers (group levels, scope totals, fields).
