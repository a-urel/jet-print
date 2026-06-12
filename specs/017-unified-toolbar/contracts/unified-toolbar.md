# Contract: Unified Context-Switching Toolbar

Behavioral contracts the implementation must satisfy, each mapped to functional requirements and the
test group that pins it. The interface surface is deliberately tiny: **two** new public symbols plus
internal composition.

---

## Public interface delta

```dart
// JetReportDesignerController — new mutator (undoable, notifies once).
void rename(String name);

// JetReportPreview — new optional callback (host wires to controller.rename).
final ValueChanged<String>? onRename;
```

Everything else is **private** under `src/`:
- `unified_top_bar.dart` — the shared shell widget.
- `workspace_mode_switch.dart` — the two-segment switch + `enum WorkspaceMode`.
- `set_template_name_command.dart` — the rename `EditCommand`.

The switch *events* reuse the already-public `JetReportDesigner.onPreviewRequested` and
`JetReportPreview.onBack`.

---

## C1 — Shared shell parity (FR-001, SC-003)

- **C1.1**: The left region (file icon + report name + edit affordance) and the center region
  (Designer|Preview switch) are produced by a single shared widget, so they occupy the **same
  position and visual style** in both Designer and Preview modes.
- **C1.2**: Only the right-hand action slot differs between modes.
- **C1.3**: The toolbar height is identical in both modes (the existing 52 px).

*Tests* (`unified_toolbar_test.dart`): pump the designer shell and the preview shell; assert the name
region and the mode switch are found at equivalent positions/sizes in both; assert the shared shell
type is used by both.

---

## C2 — Mode switch (FR-002, FR-003, FR-004, US1)

- **C2.1**: The toolbar renders a two-segment switch labelled **Designer** / **Preview** with the
  active mode highlighted.
- **C2.2 (designer shell)**: active segment = Designer; selecting **Preview** fires
  `onPreviewRequested(controller.template)`. The Preview segment is disabled when
  `onPreviewRequested == null`.
- **C2.3 (preview shell)**: active segment = Preview; selecting **Designer** fires `onBack()`. The
  Designer segment is disabled when `onBack == null`.
- **C2.4**: The toolbar never performs the swap itself — it only reflects the mode it is given and
  emits the request (host owns mode).
- **C2.5**: Selecting the already-active segment is a no-op.

*Tests* (`top_bar_test.dart`, `jet_report_preview_test.dart`): tap the inactive segment, assert the
correct callback fires once with the expected argument; assert the inactive segment disables when its
callback is null; assert the active segment is highlighted and non-firing.

---

## C3 — Inline rename (FR-006–FR-010, US2)

- **C3.1**: An edit affordance sits next to the name in **both** modes (FR-007).
- **C3.2**: Activating it makes the name editable, pre-filled with the current name and focused
  (US2.1).
- **C3.3 (Enter)**: commits the typed value; the toolbar shows it and the report carries it forward.
  An empty/whitespace value commits as `''` and the toolbar shows the localized placeholder
  (US2.2, US2.6, FR-010).
- **C3.4 (Escape)**: cancels; the prior name is retained unchanged (US2.3).
- **C3.5 (Blur, non-empty)**: commits the typed value (FR-009).
- **C3.6 (Blur, empty)**: cancels; the prior name is retained (FR-009).
- **C3.7 (designer)**: commit calls `controller.rename(value)` (undoable, single step); the name
  updates reactively via `DesignerScope`.
- **C3.8 (preview)**: commit calls `onRename(value)` **and** updates the locally-displayed name
  immediately (D5); the prior `RenderedReport` is not mutated.
- **C3.9**: an empty stored name shows the localized placeholder in both modes (FR-006).

*Tests* (`top_bar_test.dart`, `jet_report_preview_test.dart`, `rename_test.dart`): drive the inline
editor through Enter / Escape / blur(non-empty) / blur(empty) / empty-Enter; assert callback
invocation, displayed name, and (designer) `controller.template.name` + undo restoring the prior name.

---

## C4 — `rename()` controller behavior (FR-005, FR-008, Principle V)

- **C4.1**: `rename(x)` sets `controller.template.name == x`.
- **C4.2**: `rename` is a single undoable step — one `undo()` restores the prior name (and prior
  selection).
- **C4.3**: `rename` notifies listeners exactly once.
- **C4.4**: `rename(currentName)` is a no-op — no history entry, consistent with `_commit`'s identity
  guard.
- **C4.5**: a renamed template round-trips losslessly through `JetReportFormat`
  (encode→decode→encode equal); `schemaVersion` stays 1.

*Tests* (`rename_test.dart`): assert name update, single undo, one notification (listener count),
no-op on identical name, codec round-trip equality.

---

## C5 — Mode-specific actions (FR-011, SC-005, US3)

- **C5.1 (designer)**: the right slot shows the editing actions (history, clipboard, zoom, view
  toggles, arrange, open/save/export) and **none** of the preview-only actions.
- **C5.2 (preview)**: the right slot shows the viewing actions (export/print, zoom, page nav) and
  **none** of the designer-only editing actions.
- **C5.3**: each shell supplies only its own group (no runtime cross-mode filtering needed).

*Tests*: assert the presence of the mode's action icons and the **absence** of the other mode's
signature icons (e.g. no undo/redo in preview; no page-nav in designer).

---

## C6 — Responsive degradation (FR-012, SC-006)

- **C6.1**: When horizontal space is constrained, the action region collapses labels to icons or
  scrolls — the existing designer breakpoints (`_compactWidth`, `_scrollWidth`) and the preview's
  layout behavior are preserved through the shell.
- **C6.2**: The name region and the mode switch remain visible and reachable at the supported narrow
  widths (they are never the regions that collapse).

*Tests* (`unified_toolbar_test.dart`): pump at a narrow width; assert the name + switch are still
present and hit-testable while action labels collapse/scroll.

---

## C7 — Localization & accessibility (FR-013, FR-014)

- **C7.1**: `modeDesigner`, `modePreview`, `actionRenameTooltip`, `renameFieldLabel` resolve in
  en/de/tr with English fallback.
- **C7.2**: The mode switch, the edit affordance, and the inline field are keyboard-operable and
  carry accessible names (Semantics).

*Tests* (`unified_toolbar_test.dart`): resolve each key in all three locales; assert Semantics names
on the switch segments and the edit affordance; assert keyboard activation of the switch and
Enter/Escape on the field.

---

## Invariants regression (must stay green)

- Existing `top_bar_test.dart` / `jet_report_preview_test.dart` assertions (where still applicable),
  the codec suite, the layer-boundary test, and **all report goldens** stay green — this feature adds
  no render-path or serialization change.
- `public_api_test.dart` records exactly the two new symbols and nothing else changes in the surface.
