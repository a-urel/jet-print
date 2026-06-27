# Demo Left-Navigation Redesign — Design

**Date:** 2026-06-27
**Package:** `apps/jet_print_playground`
**Status:** Approved, ready for implementation plan

## Goal

Replace the top horizontal `ShadTabs` demo strip with a left navigation:

- **Wide screens (≥ 600dp):** a persistent fixed left sidebar listing all demos.
- **Narrow screens (< 600dp):** a hamburger-triggered `Scaffold` drawer holding the same list.

All chrome stays `shadcn_ui` (v0.54.0). No new packages.

## Current state (baseline)

- `apps/jet_print_playground/lib/main.dart`
  - `_PlaygroundHome` / `_PlaygroundHomeState` is the shell.
  - Demo registry built once in `initState()` as
    `List<({String value, IconData icon, Widget body})> _demoBodies`
    (11 demos: Invoice, Label, Barcode, Symbologies, Packing slip, Payroll,
    List, Ledger, Menu, Custom, Empty).
  - Selection state: `_selectedDemo` (default `'fatura'`).
  - Navigation: `ShadTabs<String>` (`scrollable: true`, keyed by `_demoTabsKey`)
    at lines ~314–327.
  - Bodies: `IndexedStack` — all demos mounted at once, only `index` swaps, so
    in-designer edits survive navigation. **This behavior must be preserved.**
  - Responsive: `LayoutBuilder` at `_narrowWidth = 600`. Narrow = toggle cluster
    above strip; wide = `Expanded(strip)` + toggles right. No `MediaQuery`.
  - Theme toggle = `ShadButton.ghost`; language cycle = `ShadButton.outline`.

## Design

### 1. Shared nav model

Keep the single registry. Derive a lightweight item view
`({String value, IconData icon, String label})` by zipping `_demoBodies` with
the localized `labels` already computed in `build()`. One source feeds both the
sidebar and the drawer — no duplication of the demo list.

### 2. `_DemoNavList` widget (new, private, same file)

Stateless. A scrollable `Column` (wrap in `SingleChildScrollView`) of
full-width selectable rows.

- Each row: `ShadButton.ghost`, left-aligned, `Icon(size: 16)` + `Text(label)`.
- Selected row: accent background (theme `secondary`) + emphasized text/weight.
- Props: `items`, `selected`, `ValueChanged<String> onSelect`.
- Reused verbatim in both layouts. Drawer usage wraps `onSelect` to also pop
  the drawer.

### 3. Responsive shell (reuse `LayoutBuilder`, `_narrowWidth = 600`)

**Wide (≥ 600):**

```
Row[
  SizedBox(width: ~220, child: <surface/bordered container> _DemoNavList),
  Expanded(Column[
    <slim top bar: Spacer + theme toggle + language toggle, right-aligned>,
    Expanded(designer body /* IndexedStack */),
  ]),
]
```

**Narrow (< 600):**

```
Scaffold(
  drawer: Drawer(child: SafeArea(_DemoNavList)),
  body: Column[
    <top bar: hamburger (ShadButton.ghost + LucideIcons.menu, left) ...
              theme + language toggles (right)>,
    Expanded(designer body /* IndexedStack */),
  ],
)
```

- Hamburger opens drawer via `Scaffold.of(context).openDrawer()` (needs a
  `Builder` for the right context, or a `GlobalKey<ScaffoldState>`).
- Selecting a demo in the drawer calls `onSelect` then `Navigator.pop(context)`.

### 4. Removed

- `ShadTabs` strip and `_demoTabsKey`.
- The two old wide/narrow header branches that positioned the strip.

`IndexedStack` body construction is unchanged.

## Out of scope (YAGNI)

- Collapsible/icon-only sidebar rail.
- Custom animated overlay (use the native `Scaffold` drawer).
- Replacing the two hardcoded labels (`Symbologies`, `Custom`) with l10n keys —
  keep as-is to stay minimal; can follow up.

## Test impact

- Playground **preview goldens will shift** (header/layout chrome changed).
  Regenerate intentionally, `chrome` platform only, per
  `spec-039-canvaskit-font-leak` / `spec-e4-web-support` lessons (Skia
  glyph-cache is layout-sensitive; `da3a261` saw goldens break from header
  widget changes).
- Add a widget smoke test: tapping a nav item updates `_selectedDemo` and swaps
  the `IndexedStack` index; existing selection persists across the switch.
- Manual GUI walk: wide layout sidebar selection; narrow layout hamburger →
  drawer open → select → drawer closes → body switched. iOS sim + chrome.

## Files touched

- `apps/jet_print_playground/lib/main.dart` (shell rewrite + new `_DemoNavList`).
- Playground golden fixtures (regenerated).
- New/updated playground widget test for nav selection.
