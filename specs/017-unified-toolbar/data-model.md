# Phase 1 Data Model: Unified Context-Switching Toolbar

This feature adds **no domain field and no serialization change**. It edits the already-existing,
already-serialized `ReportTemplate.name`. The "data" here is one new edit command, one view-only
mode enum, and the enablement/commit truth tables that govern the UI.

---

## 1. Existing entity (unchanged) — `ReportTemplate.name`

- **Source**: [report_template.dart:25](../../packages/jet_print/lib/src/domain/report_template.dart#L25)
  — `final String name;`, with `copyWith({String? name, ...})`.
- **Serialization**: always encoded by `report_codec.dart` (`'name': template.name`);
  `kReportSchemaVersion` stays **1**. No new field, no migration.
- **Validation**: none at the model level — `name` may be any string, including `''`. The
  *placeholder* is a display concern (an empty name renders the localized placeholder), not a model
  constraint. This keeps FR-010 (empty → placeholder) a UI rule and keeps the model lossless.

---

## 2. New entity — `SetTemplateNameCommand` (designer/controller/commands)

A pure `EditCommand` (same shape as `SetTextCommand`, `MoveCommand`, etc.).

| Aspect | Value |
|--------|-------|
| Fields | `final String newName;` |
| `label` | `'Rename'` (history/debug label) |
| `apply(before)` | returns `before.withTemplate(before.template.copyWith(name: newName))` |
| No-op rule | if `newName == before.template.name`, `apply` returns a document whose template is unchanged → `_commit` detects no change and records no history entry (matches the existing `_commit` identity guard) |
| Undo/redo | inherited — the snapshot is pushed by `_commit`; undo restores the prior name **and** selection |

**Exposed via** `JetReportDesignerController.rename(String name)`:

```dart
/// Renames the report to [name] as a single undoable step (FR-008).
/// An empty or whitespace-only name is stored verbatim; the UI shows the
/// localized placeholder for an empty name (FR-010). Renaming to the current
/// name is a no-op (records no history entry).
void rename(String name) => _commit(SetTemplateNameCommand(name));
```

The renamed `controller.template` is the value a host persists on save (FR-008).

---

## 3. New entity (view-only) — `WorkspaceMode`

A private enum in `workspace_mode_switch.dart`; **not exported** (the host owns mode via its own
state and the existing switch callbacks — D2).

```dart
enum WorkspaceMode { designer, preview }
```

- **Ownership**: the host. Each toolbar is *told* its active mode (the designer shell passes
  `WorkspaceMode.designer`; the preview shell passes `WorkspaceMode.preview`).
- **Transitions**: the toolbar never mutates mode; selecting the inactive segment fires the host's
  switch-request callback (`onPreviewRequested` / `onBack`), and the host performs the swap.
- **Lifetime**: ephemeral view state; never serialized.

---

## 4. Rename inline-edit state machine (view-only)

Held by the shared shell while the user is editing; not part of the model.

| State | Enter on | Trigger | Result |
|-------|----------|---------|--------|
| Viewing | — | activate edit affordance | → Editing, field pre-filled with current name, focused (US2.1) |
| Editing | typed value | **Enter** | commit typed value (even empty → placeholder); → Viewing (US2.2, US2.6) |
| Editing | typed value | **Blur**, trimmed non-empty | commit typed value; → Viewing (FR-009) |
| Editing | typed value | **Blur**, trimmed empty | **cancel** (keep prior name); → Viewing (FR-009) |
| Editing | typed value | **Escape** | cancel (keep prior name); → Viewing (US2.3) |

"Commit" = designer → `controller.rename(value)`; preview → `onRename(value)` + update local
displayed name (D5).

---

## 5. Right-region action sets (FR-011 / US3)

The shell's right slot is filled by the caller; the two sets are mutually exclusive by construction
(each mode's shell passes only its own group), so SC-005 ("none of the other mode's actions visible")
holds without runtime filtering.

| Mode | Right-slot actions (reused, existing) |
|------|----------------------------------------|
| Designer | History (undo/redo), Clipboard (cut/copy/paste), Zoom, View toggles (ruler/grid/snap), Arrange, Open / Save / Export |
| Preview | Export / Print, Zoom, Page navigation (prev / "page X of N" / next) |

The center switch + left name region are **identical** across both (one shared widget) — FR-001,
SC-003.

---

## 6. Enablement truth table

| Control | Enabled when | Source |
|---------|--------------|--------|
| Edit affordance (rename) | always (both modes) | FR-007 |
| **Preview** segment (in designer shell) | `onPreviewRequested != null` | mirrors the existing Preview action's null-guard |
| **Designer** segment (in preview shell) | `onBack != null` | mirrors the existing back-button null-guard |
| Active segment | rendered highlighted, non-interactive (already current mode) | FR-002 |

---

## Invariants

- **INV-1 (parity)**: the left (name) and center (switch) regions are one shared widget → identical
  position/style across modes (FR-001, SC-003).
- **INV-2 (single mutation path)**: every name change goes through `controller.rename` →
  `_commit`, so it is undoable and notifies exactly once (FR-005, FR-008).
- **INV-3 (lossless)**: a renamed template serializes byte-identically through the unchanged codec;
  `schemaVersion` stays 1 (Principle V).
- **INV-4 (no render fork)**: no change to `PageFrame`/`RenderedReport`/paint pipeline → all report
  goldens unchanged (Principle IV).
- **INV-5 (exclusive actions)**: each shell passes only its mode's right-slot group, so no
  cross-mode action can appear (SC-005).
