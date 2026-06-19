# Paste into selected band — design

## Problem

In the design canvas, paste always returns each copied object to its **original
source band** (matched by stable `bandId`). There is no way to paste objects
into a *different* band of the user's choosing. Selecting a band and pasting
does nothing useful — the objects still land back in their source band.

## Goal

When a band is explicitly selected and **all** objects in the clipboard come
from a single source band, paste all of them into the **selected** band.
In every other case, keep today's behavior exactly.

## Current behavior (baseline)

- Clipboard holds `ClipboardEntry = (bandId, element)` tuples
  (`controller/clipboard.dart`). `bandId` is the stable id of the band the
  element was copied from.
- `paste()` (`controller/jet_report_designer_controller.dart`) calls
  `_buildCopies(_clipboard.entries)`, which for each entry:
  - looks up the **source** band by `entry.bandId`,
  - assigns a fresh element id,
  - offsets bounds by `kPasteOffset` (+8,+8) and clamps to the source band,
  - keeps `bandId = entry.bandId`.
- `ClipboardCommand.apply` inserts each copy into the band named by its
  `bandId` via `updateBand`, appending to that band's `elements`.
- Selection is mutually exclusive: selecting a band sets `selection.bandId`
  and clears element selection (`controller/selection.dart`). So when a band is
  selected, no elements are selected.

## Trigger condition (the redirect)

In `paste()`, redirect the paste target to the selected band when **all** hold:

1. `selection.bandId != null` — a band is explicitly selected
   (an element-derived band does **not** count; literal request only); and
2. that band still exists in the current definition (`findBand` non-null); and
3. every clipboard entry shares one source `bandId` (single-source clipboard).

If any condition fails → unchanged behavior (each copy back to its source band).

## Positioning in the target band

- **Target band ≠ source band** → preserve each object's original X/Y, clamped
  to the target band (no +8/+8 nudge — nothing to overlap in a fresh band).
- **Target band = source band** (redirect is effectively a no-op) → keep the
  existing +8/+8 offset so copies don't perfectly overlap the originals.

## Mechanism

`_buildCopies` gains an optional `String? targetBandId` parameter:

- `targetBandId == null` (default) → behaves exactly as today (per-source-band
  clamp, +8/+8 offset, `bandId = entry.bandId`).
- `targetBandId != null` → for each entry:
  - resolve the **target** band by `targetBandId` (skip the entry if it no
    longer exists),
  - `bandId` of the copy becomes `targetBandId`,
  - offset = `kPasteOffset` when `targetBandId == entry.bandId`, else `(0,0)`,
  - clamp bounds to the **target** band.

`paste()` computes the trigger and passes the resolved `targetBandId` (or
`null`). `duplicate()` always passes `null` — band selection means no element
selection, so duplicate is already a no-op in that state.

No change to: clipboard storage, copy/cut, `ClipboardCommand`, keyboard
wiring, or the multi-band / no-band-selected / empty-clipboard paths.

## Scope

`paste()` only. This covers both the Cmd/Ctrl+V shortcut and the toolbar/menu
paste action, which both call `paste()`.

## Testing (TDD)

1. Single-band clipboard + a **different** band selected → all copies land in
   the selected band, at their **original** X/Y (clamped), fresh ids, and the
   copies become the new selection.
2. Single-band clipboard + the **same** (source) band selected → copies land in
   that band with the +8/+8 offset (current behavior preserved).
3. Multi-band clipboard + a band selected → unchanged (copies return to their
   respective source bands).
4. Single-band clipboard + **no** band selected → unchanged.
5. Selected band id missing from the definition → falls through to unchanged
   behavior.

## Out of scope

- Inferring a target band from a selected element.
- Choosing insertion order/index within the target band (append, as today).
- Cross-document or OS-clipboard paste.
