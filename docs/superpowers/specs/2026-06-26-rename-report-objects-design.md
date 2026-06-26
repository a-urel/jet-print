# Rename report objects — design

**Date:** 2026-06-26
**Status:** Approved (brainstorm)
**Area:** `packages/jet_print/lib/src/designer/`, `packages/jet_print/lib/src/domain/`

## Problem

In the visual designer, report objects are labeled rigidly:

- **Elements** (`TextElement`, `ShapeElement`, `ImageElement`, `BarcodeElement`,
  …) show their raw `id` (`element.id`) — e.g. `grandTotalRule` — in the
  Properties header (`properties_panel.dart` ~L244) and Outline tree
  (`outline_panel.dart` L326).
- **Bands** show a localized type label via `bandTypeLabel(band.type, l10n)`
  (`outline_panel.dart` L301) — e.g. "Group Footer".

Authors want to give objects friendly, editable names to keep a report legible,
and when no custom name is set, fall back to a sensible default rather than a
raw id.

## Decision: add an optional display `name`, keep `id` as the machine key

Introduce an optional `name` (`String?`) on `ReportElement` and `Band`. The `id`
stays as the stable, unique identity key (selection, hit-test, copy/paste,
undo, serialization, validator I1) and is **no longer the primary label**.

Why a separate field, not renaming `id`:

- The requirement "if the display name is empty, show a default (text /
  type-name)" needs the name to be **optional and possibly blank** — `id` cannot
  be blank (it is the unique identity key).
- `id` is never referenced by string in expressions (`$F{}`/`$V{}`/`$P{}`),
  bindings, group refs, or published totals, so it can stay an invisible key.
- Display `name` has **no uniqueness constraint** and may be empty — two text
  boxes may legitimately share a name.

## Display-label resolution

A single helper computes the label shown in Properties header **and** Outline,
so both surfaces always agree:

```
displayLabel(element):
  if element.name is non-blank        -> element.name
  else if element is TextElement      -> element.text        (e.g. "Subtotal", "[grandTotal]")
  else                                -> elementTypeLabel(element, l10n)   ("Rectangle", "Image", "Barcode", …)

displayLabel(band):
  if band.name is non-blank           -> band.name
  else                                -> bandTypeLabel(band.type, l10n)     (existing, reused)
```

`elementTypeLabel` is a new localized mapping mirroring the existing
`bandTypeLabel` (Text, Rectangle/Ellipse/… per `ShapeKind`, Image, Barcode).
Band fallback reuses the existing `bandTypeLabel`. Trimmed-whitespace-only names
count as blank.

## Scope

Renamable: **every `ReportElement` and every `Band`** (including structurally
roled bands — the role lives in `BandType`, untouched by `name`). Two entry
points, both driving the same command:

1. **Properties panel header** — the label (`_Header`, fed the resolved
   `displayLabel`) becomes click-to-edit: click (or pencil affordance) → inline
   text field. Enter commits, Esc cancels. The field is **prefilled with the
   current `name`** (blank if none), and its placeholder shows the fallback so
   the user sees what "empty" will display.
2. **Outline tree row** — double-click a row (element or band) → inline edit,
   same prefill/placeholder. Enter commits, Esc cancels.

## Domain changes

- `ReportElement` base: add `final String? name;` (default `null`); thread
  through every subtype constructor + `copyWith` (so `copyWith(name: …)` works,
  and existing `copyWith` calls preserve it).
- `Band`: add `final String? name;` + `copyWith`.
- **Codecs** (`domain/serialization/*_codec.dart` for each element + band):
  serialize `name` **only when non-null** (`if (name != null) 'name': name`) and
  read `json['name'] as String?`. Existing JSON without `"name"` deserializes to
  `null` → backward compatible, round-trip stable, and goldens/fixtures that
  omit `name` are unchanged.
- No change to `report_validation.dart` (I1 still guards `id` uniqueness; `name`
  is unconstrained).

## Command

Add `RenameCommand(targetId, newName)` to the undo/redo stack, reusing the
`updateElement` / band-walker mutation helpers (`controller/band_walker.dart`,
pattern from `set_text_command.dart`).

Execute:

1. Normalize `newName`: trim; empty → `null` (clears the override → fallback).
2. If normalized equals the current `name`, **no-op** (don't push a command).
3. Otherwise rewrite the target's `name` via `copyWith(name: …)` (elements and
   bands both expose `copyWith`).

No validation can fail — empty is valid (means "use default"), duplicates are
allowed. Selection is unaffected (id unchanged), so no selection re-pointing is
needed. Undo restores the prior `name`; redo re-applies.

> Supersedes the earlier draft's "block empty/duplicate with inline error" and
> "rename edits id / re-point selection" decisions — both moot under the
> separate-optional-name model.

## Testing

- **Domain unit tests:** `name` defaults to null; `copyWith(name:)` sets and
  preserves it; codec round-trips with and without `name`; legacy JSON (no
  `name` key) loads as null.
- **Label helper tests:** name set → name; TextElement blank name → its text;
  Shape/Image/Barcode blank → type label; band blank → `bandTypeLabel`;
  whitespace-only treated as blank.
- **Command tests:** set name; clear name (empty → null); whitespace → null;
  same-value no-op (no stack push); undo/redo restores.
- **Widget tests:** Properties-header inline editor and Outline double-click
  editor — prefill shows current name, placeholder shows fallback, Enter
  commits, Esc cancels, clearing reverts label to fallback.
- **Goldens:** unaffected — `name` is never painted onto the canvas; codecs omit
  `name` when null so existing serialized fixtures are byte-identical.

## Out of scope

- Renaming the `id` (it stays an internal key).
- Uniqueness/validation on `name`.
- Bulk rename / find-replace.
- Renaming non-object identifiers (group levels, scope totals, fields).
