# Double-tap focuses the Properties pane (replaces inline text editing)

**Date:** 2026-06-10
**Status:** Approved

## Goal

Double-tapping any report object on the designer canvas selects it, brings the
right panel to the **Properties** tab (opening the collapsed overlay first in
the narrow layout), and moves keyboard focus into the most relevant inspector
field — the **Text** field for a `TextElement`, the **X** field for every other
element type. The inline (in-place) text editor is removed entirely.

## Background

Today a double-tap on a `TextElement` opens an `InlineTextEditor` overlay
positioned over the element (`design_canvas.dart` `_handleTapDown`,
`_editingId`, and the positioned editor block). Double-tap does nothing for
non-text elements. The right panel (`DesignerRightPanel`) is a stateless
`ShadTabs` with a fixed initial tab (Data Source) and `maintainState: false`,
so inactive tab bodies leave the tree. In the narrow (<1024 px) layout the
whole right panel is absent from the tree until the user expands the overlay
(`_rightOpen` in `_JetReportDesignerState`).

## Design

### 1. Controller: a one-shot "focus properties" intent

`JetReportDesignerController` gains a pending-focus flag — an ephemeral UI
intent, not part of the template model and never serialized:

- `void requestPropertiesFocus()` — sets `_pendingPropertiesFocus = true` and
  `notifyListeners()`.
- `bool get pendingPropertiesFocus` — non-consuming peek, used by long-lived
  widgets (shell, right panel) to react without claiming the event.
- `bool takePropertiesFocus()` — returns the flag and clears it; called exactly
  once by the final consumer (the Properties panel) after it actually moves
  keyboard focus.

A flag (rather than a counter/event) is deliberate: in the narrow layout the
panel that must consume the intent is not mounted when the intent fires. The
flag survives until the overlay opens, the tab body mounts, and the panel
consumes it.

### 2. Canvas: rewire double-tap, delete inline editing

In `design_canvas.dart` `_handleTapDown`, the existing manual double-tap
detection (300 ms window, 24 px slop — kept manual so single-tap select stays
undelayed) is preserved, with two changes:

- The `is TextElement` guard is dropped — double-tap works on **any** element.
- Instead of entering inline-edit (`_editingId = hit`), it calls
  `controller.requestPropertiesFocus()`. Selection was already set by the
  first tap of the pair.

Removed: the `_editingId` field, the positioned `InlineTextEditor` render
block, and `inline_text_editor.dart` itself. `controller.setText` remains —
the Properties panel is now the only text-editing surface.

### 3. Right panel: programmatic tab switching

`DesignerRightPanel` becomes a `StatefulWidget` owning a
`ShadTabsController<String>`:

- **On mount:** initial tab is Properties when
  `controller.pendingPropertiesFocus` is set (covers the narrow-overlay
  fresh-mount path), otherwise Data Source as today.
- **While mounted:** listens to the designer controller; when a pending
  request appears, selects the Properties tab. Does not consume the flag.

### 4. Shell: open the narrow overlay

`_JetReportDesignerState` listens to its controller; when a pending request
appears while the narrow layout has the overlay closed, it
`setState(() => _rightOpen = true)`. Idempotent; does not consume the flag.
No-op in the wide layout.

### 5. Properties panel: focus the target field

`PropertiesPanel` becomes stateful and owns two `FocusNode`s passed into the
target fields via a new optional `focusNode` parameter on `_NumberField` and
`_TextField` (fields fall back to their own internal node when not provided;
blur-commit listeners attach to whichever node is in effect).

On build it schedules a post-frame callback: if `takePropertiesFocus()`
returns true **and** the selection is a single element, focus the Text field
(`TextElement`) or the X field (anything else). Post-frame + one-shot take
guarantees focus fires once, only after the tab body exists, and ordinary
rebuilds never re-steal focus.

### Error handling

If the selection is no longer a single element when the flag is consumed, the
panel takes the flag and skips focusing — no crash, no stuck flag. The flag is
also cleared naturally on the next consume; it carries no model state, so undo
/ redo / open are unaffected.

## Data flow

```
double-tap on element
  → canvas: controller.select(hit) (first tap) + requestPropertiesFocus()
  → notifyListeners()
     ├─ shell (narrow only): open overlay            [peek]
     ├─ right panel: select Properties tab           [peek / initial tab]
     └─ properties panel (post-frame): takePropertiesFocus()
        → focus Text field (TextElement) or X field  [consume]
```

## Testing

Replace `test/designer/canvas/inline_text_edit_test.dart` with
`double_tap_properties_focus_test.dart`:

1. Double-tap a text element → Properties tab active, Text field has focus.
2. Double-tap a shape element → Properties tab active, X field has focus.
3. Single tap selects but does **not** switch tabs or move focus.
4. Narrow layout: double-tap opens the overlay with the Properties tab active
   and the target field focused.
5. Editing text through the Properties Text field remains committed and
   undoable (replaces the old inline-edit undo coverage).

## Docs / changelog

- Update `JetReportDesigner` dartdoc ("inline-edit text" → double-tap jumps to
  the Properties inspector).
- CHANGELOG entry: behavior change (inline editor removed) + new controller
  members (`requestPropertiesFocus`, `pendingPropertiesFocus`,
  `takePropertiesFocus`).

## Out of scope

- In-place editing of any kind (explicitly removed).
- Double-tap behavior for bands / empty paper (unchanged: tap-up selection
  classification only).
- Any richer per-type property editors.
