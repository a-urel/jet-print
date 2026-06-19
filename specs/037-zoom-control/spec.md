# Feature Specification: Designer Zoom Control

**Feature Branch**: `037-zoom-control`
**Created**: 2026-06-19
**Status**: Draft
**Input**: The designer top bar's zoom group is a static trio — `[ – ] [87%] [ + ]`
— where the percentage is a non-editable label that, when tapped, fits the page
to the viewport **width** only. There is no way to type a zoom level, jump to a
preset, return to 100%, or fit the whole page. This feature upgrades the middle
of that group into a proper **zoom control**: an editable percentage field with a
dropdown menu offering sticky fit modes (Fit width, Fit page), 100%, and preset
percentages. Designer/UI-only — no engine, model, serialization, or render-path
change.

## Problem

The current zoom affordance (`designer_top_bar.dart` lines 161–189) is minimal:

1. **The percentage is read-only.** An author cannot type an exact zoom level
   (e.g. `130`); they can only step by ×1.25 via the `[ + ]` / `[ – ]` buttons
   or ×1.1 via Ctrl/Cmd-scroll. Hitting a specific number is fiddly.
2. **Only fit-to-width exists.** Tapping the `87%` label fits the page width to
   the viewport (`fitToView` → `fitRequest++` → the canvas's `_fitScale`). There
   is no **fit whole page** (width *and* height), no **100% / actual size**
   anchor, and no quick **preset** percentages.
3. **Fit is one-shot.** The canvas fits on first load and on each explicit fit
   request, but does **not** re-fit when the viewport changes (window/panel
   resize). After any resize the page is no longer fit; the author must tap
   again.

The view state (`_viewScale`, `_viewPan`, `_fitRequest`) and the fit seam (the
controller *requests* a fit; the canvas, which owns the viewport, *computes* it
via `setView`) are already in place. This feature extends that seam — it does not
replace it.

## Clarifications

### Session 2026-06-19

- Q: What should the improved control look like / how should it behave? → A:
  **Editable % field + dropdown.** The middle of the zoom group becomes a small
  editable percentage field (type a value, commit on Enter/blur) **and** carries
  a dropdown caret that opens a menu of fit modes and presets. The `[ – ]` /
  `[ + ]` buttons remain.
- Q: Which menu entries? → A: **Fit width**, **Fit page**, **100% (actual
  size)**, and **preset percentages**. (100% doubles as the actual-size anchor
  and as the middle preset — one row, no redundancy.)
- Q: Should a selected fit mode be sticky or one-shot? → A: **Sticky until
  changed.** Picking Fit width / Fit page keeps re-fitting as the viewport
  resizes. Any manual zoom (`[ + ]` / `[ – ]`, typing a %, Ctrl/Cmd-scroll, or
  picking a preset) drops back to a plain percentage (fit mode → `none`).
- Q: While a fit mode is active, what does the field show? → A: **Always the
  computed %** (a live number, always editable). The active fit mode is shown by
  a **checkmark** next to its menu row — the field never shows mode text.
- Q: Default fit mode on load? → A: **Fit width** (sticky). This preserves
  today's fit-on-load behavior and additionally re-fits on resize.
- Q: Preset set? → A: `50%`, `75%`, `100%`, `150%`, `200%`.

## Scope

**In scope**

- A new **`ZoomControl`** widget (`layout/zoom_control.dart`) replacing the
  static `46`-px percentage label between the existing `[ – ]` / `[ + ]`
  buttons. It is an **editable `ShadInput`** showing the live `%` plus a
  **dropdown caret** opening a **`ShadContextMenu`** of fit modes and presets.
- A **view fit-mode** model: a new `enum JetViewFitMode { none, width, page }`
  (`controller/view_fit_mode.dart`) and controller state `_viewFitMode`
  (default `width`), getter `viewFitMode`, and `setViewFitMode(mode)`.
- New controller methods that route **user intent** and clear the fit mode:
  `setZoomPercent(double percent)` (typed field / presets) and
  `zoomBy(double factor)` (Ctrl/Cmd-scroll). Existing `zoomIn` / `zoomOut` also
  clear the mode. The low-level `setView` / `setViewScale` stay **mode-agnostic**
  (the canvas uses them to *apply* a computed fit without clobbering the mode).
- A new **fit-page** computation and **sticky re-fit on resize**: a pure
  `zoom_math.dart` with `fitWidthScale` (extracted from the canvas's private
  `_fitScale`) and `fitPageScale`; the canvas re-fits when the viewport changes
  while a fit mode is active.
- **Localization** of the new chrome strings (`actionZoomFieldTooltip`,
  `menuZoomFitWidth`, `menuZoomFitPage`) across the three `.arb` files
  (`en` / `de` / `tr`) and generated `JetPrintLocalizations`. Preset rows are
  numeric (`50%`…) and need no string.

**Out of scope**

- Any engine, model, serialization, `validate()`, or render/export change. View
  state is not part of the model or history (it is transient designer state) and
  stays that way.
- Keyboard shortcuts for zoom (e.g. Cmd+0 → 100%, Cmd+1 → fit). The foundation
  makes them trivial later, but they are not part of this slice.
- Fit-to-selection, height-only fit, persisting zoom across sessions, and a
  pan/scroll-position overhaul. The fit/pan seam is reused as-is.
- Changing the `[ – ]` / `[ + ]` buttons' ×1.25 step or the Ctrl/Cmd-scroll
  ×1.1 factor.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Type an exact zoom level (P1)

An author clicks the zoom field, types `130`, and presses Enter. The view zooms
to 130%, the field shows `130%`, and the fit mode drops to `none`. Typing a value
above 400 or below 25 clamps to the bound; typing a non-number reverts the field
to the current value. Blurring the field commits the same way as Enter.

### User Story 2 - Fit the whole page (P1)

The author opens the dropdown and picks **Fit page**. The view scales so the
entire page (width *and* height) fits within the viewport, the **Fit page** row
shows a checkmark, and the field shows the resulting computed `%` (e.g. `42%`).
Resizing the window keeps the whole page fit (sticky). Picking **Fit width**
switches to width-only fit; the checkmark moves.

### User Story 3 - Jump to a preset / actual size (P1)

The author opens the dropdown and picks **100%**. The view zooms to exactly
100% (actual size), the fit mode drops to `none`, and the **100%** row shows a
checkmark (because the current % now equals a preset). Picking `200%` zooms to
200%; the checkmark moves to `200%`.

### User Story 4 - Sticky fit survives resize (P1)

On load, the default fit mode is **Fit width**, so the page fits the viewport
width (today's behavior). The author drags a side panel wider, shrinking the
canvas viewport. The page **re-fits** to the new width automatically — no manual
re-tap. (Today the page would stay at its old scale.)

### User Story 5 - Manual zoom clears the fit mode (P2)

While **Fit width** is active, the author clicks `[ + ]` (or Ctrl/Cmd-scrolls,
or types a %). The fit mode drops to `none`, the checkmark disappears from the
menu, and subsequent resizes no longer re-fit. The author is back in manual
zoom until they pick a fit mode again.

## Requirements *(mandatory)*

### Functional

- **FR-001**: The designer top bar MUST replace the static percentage label
  (between the `[ – ]` and `[ + ]` zoom buttons) with a **`ZoomControl`** widget.
  The `[ – ]` / `[ + ]` buttons MUST remain, unchanged in behavior.
- **FR-002**: `ZoomControl` MUST present an **editable** percentage field
  (`ShadInput`) that **always** displays the live computed zoom as a rounded
  whole-number percent (`"${round(viewScale * 100)}%"`), even while a fit mode is
  active. The field MUST carry the existing
  `ValueKey('jet_print.designer.action.zoomLevel')` so existing tests/automation
  keep resolving it.
- **FR-003**: Committing the field (on Enter or on blur) MUST parse the entered
  value (tolerating a trailing `%` and surrounding whitespace), and on a valid
  number call `controller.setZoomPercent(value)`. An invalid/empty entry MUST
  revert the field to the current value without changing the zoom. The field MUST
  NOT clobber in-progress typing when the controller's scale changes while the
  field is focused (the `_NumberField` discipline).
- **FR-004**: `controller.setZoomPercent(double percent)` MUST set the view scale
  to `percent / 100`, clamped to `kMinZoom..kMaxZoom` (25%–400%), and MUST set
  the fit mode to `JetViewFitMode.none`.
- **FR-005**: `ZoomControl` MUST show a **dropdown caret** (e.g.
  `LucideIcons.chevronDown`) that toggles a **`ShadContextMenu`** (via a
  `ShadPopoverController`) containing, in order: **Fit width**, **Fit page**, a
  divider, then preset rows **50%**, **75%**, **100%**, **150%**, **200%**.
- **FR-006**: Each menu row MUST use the established **leading-checkmark**
  selected-state pattern (`ShadContextMenuItem` with a `LucideIcons.check`
  leading icon, visible only when selected). **Fit width** / **Fit page** are
  checked when `viewFitMode` equals `width` / `page` respectively; a preset row
  is checked when `viewFitMode == none` **and** `round(viewScale * 100)` equals
  that preset. At most one row is checked at a time.
- **FR-007**: Picking **Fit width** MUST call `controller.setViewFitMode(width)`;
  **Fit page** MUST call `setViewFitMode(page)`; a preset row MUST call
  `controller.setZoomPercent(n)`. Selecting a row MUST close the menu.
- **FR-008**: A new `enum JetViewFitMode { none, width, page }` MUST be defined
  (`controller/view_fit_mode.dart`). The controller MUST hold `_viewFitMode`
  (default **`width`**), expose `viewFitMode`, and provide
  `setViewFitMode(JetViewFitMode mode)` which sets the mode, increments
  `_fitRequest`, and notifies listeners (so the canvas recomputes the fit).
- **FR-009**: The controller's **manual-zoom** entry points MUST set the fit mode
  to `none`: `zoomIn()`, `zoomOut()`, `setZoomPercent(...)`, and a new
  `zoomBy(double factor)` (`setViewScale(viewScale * factor)` after clearing the
  mode). The canvas's Ctrl/Cmd-scroll handler MUST call `zoomBy` instead of
  `setViewScale` directly.
- **FR-010**: The low-level `setView(scale, pan)` and `setViewScale(scale)` MUST
  remain **mode-agnostic** (they MUST NOT change `_viewFitMode`), so the canvas
  can *apply* a computed fit without clearing the active mode. (This is the seam
  that keeps sticky fit from clearing itself.)
- **FR-011**: A pure-function file `canvas/zoom_math.dart` MUST provide
  `fitWidthScale(JetSize content, Size viewport, double padding)` (the current
  `_fitScale` logic) and `fitPageScale(JetSize content, Size viewport, double
  padding)` = `min(usableWidth / content.width, usableHeight / content.height)`,
  both clamped to `kMinZoom..kMaxZoom` and both guarding against non-positive
  usable dimensions (returning `1.0` rather than `0`/`NaN`/`Infinity`). The
  canvas MUST use these functions (no inline duplicate math).
- **FR-012**: The canvas MUST recompute and apply the fit when **any** of:
  `!_viewInitialized`, `controller.fitRequest` changed since last applied, or
  (`controller.viewFitMode != none` **and** the viewport size changed since the
  last applied fit). The applied scale MUST be `fitPageScale(...)` when
  `viewFitMode == page` and `fitWidthScale(...)` otherwise (covering `width` and
  the first-load fit, since the default mode is `width`), applied via
  `controller.setViewScale(...)` (mode-agnostic). The canvas MUST track the last
  fitted viewport so a steady viewport does not re-fit every frame.
- **FR-013**: When `viewFitMode == none` (after the initial load fit), the canvas
  MUST NOT auto-fit on resize — manual zoom is preserved across resizes exactly
  as today.
- **FR-014**: New chrome strings — `actionZoomFieldTooltip` (field/caret
  tooltip), `menuZoomFitWidth`, `menuZoomFitPage` — MUST be added to the `en`,
  `de`, and `tr` `.arb` files and generated `JetPrintLocalizations`. The now-
  unused `actionZoomFitTooltip` key MUST be removed. Preset rows render numeric
  percentages and require no new strings.

### Key Entities

- **`JetViewFitMode`** *(new enum, controller)* — `{ none, width, page }`; the
  sticky view fit mode. `none` = manual percentage.
- **`ZoomControl`** *(new widget, designer UI)* — editable `ShadInput` percent
  field + dropdown-caret `ShadContextMenu`; reads `controller.viewScale` /
  `viewFitMode`, drives `setZoomPercent` / `setViewFitMode`.
- **`zoom_math.dart`** *(new, canvas)* — pure `fitWidthScale` / `fitPageScale`;
  the single source of fit arithmetic, shared by the canvas and unit-testable in
  isolation.
- **View state** *(existing, reused/extended)* — `_viewScale`, `_viewPan`,
  `_fitRequest`, plus new `_viewFitMode`; transient designer state, not part of
  the model or undo/redo history.

## Success Criteria *(mandatory)*

- **SC-001**: Typing `130` + Enter in the zoom field sets `controller.viewScale`
  to `1.30` and `viewFitMode` to `none`; typing `1000` clamps to 400%; typing
  `abc` reverts to the prior value with no zoom change.
- **SC-002**: Picking **Fit page** sets `viewFitMode == page`, and the rendered
  view scales so the whole page fits the viewport (verified via `fitPageScale`
  against a known content/viewport); the **Fit page** row shows the checkmark.
- **SC-003**: Picking **100%** (or any preset) sets `viewFitMode == none` and
  `viewScale` to that value; exactly the matching preset row is checked, and
  while a fit mode is active no preset row is checked.
- **SC-004**: With a fit mode active, changing the viewport size re-fits the view
  (sticky); with `viewFitMode == none`, changing the viewport size leaves
  `viewScale` unchanged.
- **SC-005**: `zoomIn` / `zoomOut` / `setZoomPercent` / `zoomBy` each set
  `viewFitMode` to `none`; the low-level `setViewScale` / `setView` leave
  `viewFitMode` unchanged (unit-tested).
- **SC-006**: `fitWidthScale` and `fitPageScale` return correct clamped values
  and never return `0`, `NaN`, or `Infinity` for zero/negative usable
  dimensions (unit-tested).
- **SC-007**: New `.arb` keys resolve in `en` / `de` / `tr` with no missing-key
  fallback; `actionZoomFitTooltip` is gone with no remaining references.
- **SC-008**: The full `jet_print` suite is green, `flutter analyze` is clean,
  and existing goldens are **byte-identical** (designer/transient-state-only
  change; no engine output or `schemaVersion` change).
