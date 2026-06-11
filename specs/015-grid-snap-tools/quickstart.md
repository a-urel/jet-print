# Quickstart: Grid & Snap Helper Tools

## For the end user (designer UX)

The design canvas top bar has three helper-tool buttons. With the rulers tool already done, this
feature finishes the other two:

- **Grid** (grid icon) — **shows/hides** a light 5 mm alignment grid over the page content. On by
  default. Purely visual: turning it off does not change snapping.
- **Snap** (magnet icon) — turns **snapping** on/off for move and resize. On by default. When on,
  element edges align to the nearest 5 mm grid line (and to neighbouring elements and band edges),
  with a guide line shown while you drag.

The two buttons are **independent** — any combination works:

| Grid | Snap | Result |
|------|------|--------|
| on | on | See the grid, and edges lock to it (default). |
| on | off | See the grid for manual eyeballing; elements move freely. |
| off | on | Clean page, but edges still lock to the (invisible) 5 mm grid + siblings/bands. |
| off | off | Clean page, fully free movement. |

Hold the **snap-bypass modifier** (Alt/Option) during a drag to suspend snapping for that drag only.

The grid is a **workspace aid**: it never appears in the preview, the print output, the exported
file, or the saved template.

## For the host application (library consumer)

**Zero wiring required.** The grid and snap tools ship inside `JetReportDesigner` and are controlled
by the built-in top bar, on by default. No new public API:

```dart
// Already-existing controller surface — unchanged signatures, refined meaning:
controller.gridEnabled;            // bool — is the grid DRAWN (visibility only)
controller.setGridEnabled(true);   // show/hide the grid
controller.snapEnabled;            // bool — is snapping active (grid + sibling + band)
controller.setSnapEnabled(true);   // toggle all snapping
```

> Behaviour change to be aware of when upgrading: `gridEnabled` previously gated grid **snapping**;
> it now controls grid **visibility** only. Grid snapping is governed solely by `snapEnabled`. The
> interactive snap step also changes from 8 pt to **5 mm** — this affects new placements only;
> stored report coordinates are untouched.

## Verifying locally

```bash
# Unit + widget tests for this feature (from repo root):
flutter test packages/jet_print

# Targeted:
flutter test packages/jet_print/test/designer/canvas/grid_geometry_test.dart
flutter test packages/jet_print/test/designer/canvas/grid_test.dart
flutter test packages/jet_print/test/designer/canvas/grid_alignment_test.dart
flutter test packages/jet_print/test/designer/canvas/snapping_test.dart
```

Manual walk in the playground (`apps/jet_print_playground`): open the invoice, confirm the 5 mm grid
is visible by default; toggle the grid button (grid appears/disappears, snapping unaffected); toggle
the magnet (drag an element and watch edges lock to grid lines / move freely); zoom out far (grid
thins, never a solid fill); open the preview (no grid).
