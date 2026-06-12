# Phase 1 — Quickstart: Clipboard Operations in the Designer UI

## What changes for the user

The designer's cut/copy/paste — until now keyboard-only — become **mouse-reachable** in two places:

1. **Toolbar**: a Cut / Copy / Paste group joins the top bar, right after Undo/Redo.
2. **Canvas context menu**: right-click anywhere on the canvas for Cut, Copy, Paste, Duplicate,
   Delete — each acting on the current selection, each showing its keyboard shortcut.

Enablement is automatic: Cut/Copy (and Duplicate/Delete) light up when elements are selected; Paste
lights up the moment something is on the clipboard. Tooltips and menu labels are localized
(en/de/tr) and carry the platform shortcut (⌘ on macOS, Ctrl elsewhere).

## Host wiring required

**None.** Like the grid, rulers, and arrange tools before it, this is entirely internal to
`JetReportDesigner`. Embedding apps get the toolbar group and context menu automatically — no new
constructor arguments, no callbacks, no host code:

```dart
JetReportDesigner(
  initialReport: template,
  dataSchema: schema,
  // Cut/Copy/Paste toolbar + canvas context menu are built in. Nothing to wire.
)
```

## Trying it in the playground

```bash
flutter run -d macos -t apps/jet_print_playground/lib/main.dart
```

Then, mouse-only:
- Select an element → click **Copy** in the toolbar → click **Paste**: an offset duplicate appears,
  selected.
- Right-click an element → **Cut**; right-click empty canvas → **Paste**: it returns.
- Right-click with two elements selected on empty canvas → the selection is preserved and **Cut**
  removes both.
- Hover any clipboard button → tooltip shows the action and its shortcut.

## Verifying

```bash
# From repo root (note: `flutter` leaves cwd inside the package — always cd back to root for git).
flutter test packages/jet_print
```

Expected: new clipboard-reactivity, top-bar, context-menu, and l10n tests pass; the existing
`keyboard_clipboard_test.dart`, codec, and golden suites stay green (no output or saved-file
change); `public_api_test` reflects the two added getters.

## Surface area touched (for reviewers)

| File | Change |
|------|--------|
| `controller/jet_report_designer_controller.dart` | `copy()` now notifies; add `canCopy`, `canPaste` getters |
| `layout/designer_top_bar.dart` | new Cut/Copy/Paste `_IconButton` group after History |
| `canvas/design_canvas.dart` | `onSecondaryTapDown` → hit-test + select (FR-010); wrap content in `ShadContextMenuRegion` |
| `l10n/jet_print_{en,de,tr}.arb` | `actionCutTooltip`, `actionCopyTooltip`, `actionPasteTooltip`, `menuDuplicate`, `menuDelete` |
| `test/public_api_test.dart` | record `canCopy`, `canPaste` |

No domain, codec, schema, or render-pipeline files are touched.
