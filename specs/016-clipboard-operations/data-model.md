# Phase 1 — Data Model: Clipboard Operations in the Designer UI

This feature adds **no new domain entities and no serialized fields**. Every entity it relies on
already exists; the work surfaces them through UI. This document records the entities the UI
*reads*, the (view-only) enablement state it *derives*, and the strictly-additive controller surface
— nothing here is persisted or versioned.

---

## Existing entities (read-only for this feature)

### Clipboard *(unchanged)*

[`clipboard.dart`](../../packages/jet_print/lib/src/designer/controller/clipboard.dart) — the
session-scoped, in-memory holder. **Not** the OS clipboard; not serialized.

| Member | Type | Role here |
|--------|------|-----------|
| `isEmpty` | `bool get` | The sole input to Paste enablement (read via new `canPaste`). |
| `entries` | `List<ClipboardEntry> get` | Read by `paste()` only; UI never reads it directly. |
| `set(entries)` | `void` | Called by `copy()`; UI never calls it directly. |

`ClipboardEntry` = `({int bandIndex, ReportElement element})` — unchanged.

### Selection *(unchanged)*

[`selection.dart`](../../packages/jet_print/lib/src/designer/controller/selection.dart) — immutable.
Drives Cut/Copy/Duplicate/Delete enablement and defines what they act on.

| Member | Type | Role here |
|--------|------|-----------|
| `ids` | `List<String>` | `ids.isNotEmpty` ⇒ one or more **elements** selected (input to `canCopy`). |
| `isReport` / `bandIndex` | `bool` / `int?` | When a band/report is selected, `ids` is empty ⇒ Cut/Copy disabled (edge case). |

### Report Element *(unchanged)*

The unit cut/copied/pasted. Paste produces a deep copy with a fresh id + offset position
(`_buildCopies`, controller:825). No field changes.

---

## Derived view state (computed, not stored)

These are **pure functions of existing state**, recomputed each rebuild — no new fields, no
persistence. Both UI surfaces read the *same* predicates so they cannot diverge (FR-012).

| Predicate | Definition | Gates |
|-----------|------------|-------|
| `canCopy` | `selection.ids.isNotEmpty` | Cut, Copy, Duplicate, Delete enablement (FR-004, FR-005a) |
| `canPaste` | `!_clipboard.isEmpty` | Paste enablement (FR-005) |

Enablement truth table (SC-003) — every cell is covered by a test:

| Selection has elements | Clipboard has content | Cut | Copy | Paste | Duplicate | Delete |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| no  | no  | ✗ | ✗ | ✗ | ✗ | ✗ |
| no  | yes | ✗ | ✗ | ✓ | ✗ | ✗ |
| yes | no  | ✓ | ✓ | ✗ | ✓ | ✓ |
| yes | yes | ✓ | ✓ | ✓ | ✓ | ✓ |

---

## Additive controller surface (Constitution I — reviewed)

Strictly additive; mirrors the existing `canUndo`/`canRedo` idiom. Recorded in
[`public_api_test.dart`](../../packages/jet_print/test/public_api_test.dart).

| Symbol | Kind | Definition | Notes |
|--------|------|-----------|-------|
| `canCopy` | `bool get` | `_document.selection.ids.isNotEmpty` | New public getter |
| `canPaste` | `bool get` | `!_clipboard.isEmpty` | New public getter (clipboard is private) |
| `copy()` | behavior change | now calls `notifyListeners()` after `set` | Same signature; still **no** undo entry (FR-009) |

`cut()`, `paste()`, `duplicate()`, `delete()` — **unchanged** (already notify via `_commit`).

---

## State transitions (behavioral, already implemented — pinned by tests)

```
            Copy / Cut                         Paste / Duplicate
 selection ───────────► clipboard filled ────────────────────► offset copies inserted + selected
    │                   (canPaste: true)                        (one undoable step; FR-008/009)
    │
    └─ Cut also removes the selection ⇒ selection empties ⇒ canCopy:false, canPaste stays true
       (edge case: "Selection lost after Cut")
```

- **Copy**: clipboard ← selection; document unchanged; **notifies** (D1) ⇒ `canPaste` flips true.
  No undo entry (FR-007, FR-009).
- **Cut**: Copy then Delete — one undoable step; selection becomes empty (FR-006).
- **Paste**: clipboard → fresh-id, offset, band-clamped copies, inserted + selected; one undoable
  step (FR-008). No-op when clipboard empty.
- **Duplicate**: like Paste from the *current selection* without touching the clipboard; one
  undoable step (FR-005a).
- **Delete**: removes the selection; one undoable step.
- **Dismiss menu**: no state change, no document change (FR-011).

---

## Non-impact (FR-016, SC-006)

- **Domain model**: no new/changed fields.
- **Serialization**: no codec change; `schemaVersion` untouched; no migration. Saved reports load
  and render byte-identically.
- **Render pipeline**: untouched; preview/export/print output and all goldens unchanged.
