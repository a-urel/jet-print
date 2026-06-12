# Behavioral Contracts: Format Properties — Font & Color Editors

**Feature**: `021-format-properties` | **Date**: 2026-06-13
**Interface type**: designer Properties-panel UI contracts + public controller API +
serialization wire contracts. Each contract names the test group that pins it.

## C1 — Section gating (FR-017)

| Selection | Font section | Appearance (fill/outline) section | Barcode color |
|---|---|---|---|
| `TextElement` | ✅ | — | — |
| `ShapeElement` (closed form) | — | ✅ fill + outline color + width | — |
| `ShapeElement` (`ShapeKind.line`) | — | ✅ outline color + width only, **no fill control** | — |
| `BarcodeElement` | — | — | ✅ |
| `ImageElement` / band / report / none / multi | — | — | — |

*Tests*: widget — `properties_editor_test.dart` (one case per row).

## C2 — Font section contents & binding (FR-001…FR-005, AS-1.1)

Selecting a text element shows, bound to its current style: family select, size field
(stepper), B / I / U toggle group, color field, alignment segments (left/center/right).
A stored `justify` alignment shows **no active segment** and is preserved verbatim on
unrelated edits until the user picks an alignment (clarified 2026-06-13 — justified
rendering is a follow-up). Every control displays the **effective** value, including for
pre-feature elements (FR-006).

*Tests*: widget — section renders all controls; values match a styled element and a
default (fallback) element.

## C3 — Family picker (FR-001, unknown-family edge case)

- Lists exactly the designer registry's `families` (default first), each item previewed in
  its own typeface.
- Pick → one `setTextStyle` commit → canvas re-renders in that family → persists (C10).
- Element references an unregistered family ⇒ that name appears as an extra item, selected,
  marked unavailable (localized); rendering falls back to default; the stored value survives
  save/reload untouched unless the user picks another family.

*Tests*: widget — enumeration & preview; unavailable-family display; unit — codec preserves
the unknown family string through load→save.

## C4 — Size field (FR-002, AS-1.3, font-size extremes edge case)

- Numeric entry + ±1 steppers; commit on Enter/blur or stepper click.
- Clamp to **[4, 144]**: out-of-range commits the clamped value; non-numeric input is
  rejected, the previous value restored, no commit.
- Stroke-width field obeys the same contract with range **[0, 20]** (C7).

*Tests*: widget — type 500 ⇒ commits 144; type "abc" ⇒ restores prior, no history entry;
stepper at bound stays at bound (no-op ⇒ no history).

## C5 — B/I/U toggles (FR-003, AS-1.4, clarification #1/#2)

- Bold active ⟺ `weight == bold`; press inactive ⇒ commit `weight: bold`; press active ⇒
  commit `weight: normal`. A stored `medium`/`semiBold` shows Bold inactive and is preserved
  verbatim until the toggle is operated.
- Italic and Underline map 1:1 to their booleans.
- Each press = one commit = one undo step; toggles visibly indicate active state.

*Tests*: widget — toggle states for all four weights; medium preserved on unrelated edits;
press-on-medium ⇒ bold; unit — `SetTextStyleCommand` single-step/no-op semantics.

## C6 — Shared color editor (FR-009, FR-010, AS-1.5; invalid-hex & alpha edge cases)

- Trigger shows current swatch + hex (`#RRGGBB`, or `#AARRGGBB` when alpha ≠ `FF`).
- Popover: palette swatches + hex input (+ **None** entry only where C7 allows).
- Swatch pick / valid 6-digit hex ⇒ commit with **stored alpha preserved**; valid 8-digit
  hex ⇒ commit with that alpha.
- Malformed hex ⇒ reject, restore last valid value, visible feedback, no commit.

*Tests*: widget — display formats; alpha-preserving pick on a translucent color; 8-digit
entry; invalid entries (`#12`, `red`, `#GGGGGG`) restore + no history.

## C7 — Shape appearance (FR-007, FR-008, AS-2.x; invisible-shape edge case)

- Fill color editor offers **None** ⇒ commits `fill: null`; interior not painted; editor
  shows the none state distinctly.
- Outline color editor offers **None** ⇒ commits `stroke: null`.
- Width 0 ⇒ outline not rendered on any path, `stroke` color **retained**; width back > 0
  restores the colored outline.
- Fill `null` + stroke `null` ⇒ canvas still shows the design-time selectable placeholder
  affordance (element remains hit-testable); preview/export render nothing for it.
- Line shapes: fill control absent (C1); stroke `null` line keeps its existing default-black
  design-time render (`shape_element_renderer.dart:51` behavior unchanged).

*Tests*: widget — none states & gating; unit — renderer emits `stroke: null` when width ≤ 0;
golden — unfilled/unstroked combinations across canvas/preview/export.

## C8 — Barcode color (FR-011, AS-3.x)

Shared color editor (no None) bound to `BarcodeElement.color`; pick ⇒ one
`setBarcodeColor` commit; placeholder rendering reflects the color on canvas, preview, and
export; undo restores.

*Tests*: widget — editor presence/commit; unit — command + codec (color omitted when black);
renderer test — placeholder primitives carry `el.color`.

## C9 — Undo/redo (FR-013, SC-003, AS-1.7; rapid-changes edge case)

Every committed change from any editor in C2–C8 is exactly **one** undo step; undo restores
both model and the panel's displayed values; redo replays. Typing without committing creates
no history. Committing an unchanged value creates no history. Selection change mid-edit
discards uncommitted input and re-binds editors to the new selection.

*Tests*: widget — per-editor undo round-trip; no-op commits record nothing; selection-switch
discard.

## C10 — Persistence wire contract (FR-014, SC-004, FR-006)

- `underline: true` serializes; `false` is omitted; absent ⇒ `false` on load.
- `fill`/`stroke: null` omitted on write, `null` on read (existing rule, now reachable from
  the UI). Alpha survives round-trip (`#AARRGGBB`).
- A pre-feature report loads and re-saves **byte-identically**.
- Schema version stays `1`; no migration.

*Tests*: unit — codec round-trips per element type; pre-feature fixture byte-compare;
`public_api_test.dart` records `underline`, `copyWith`s, and the three controller methods.

## C11 — Rendering parity (FR-015, SC-002, Constitution IV)

For every editable attribute, canvas, preview (PNG path), and PDF export agree:
family/size/weight/italic/color/alignment ride the existing shared pipeline; **underline**
geometry comes from the single `underlineFor` helper in both painters; shape fill/stroke and
barcode tint ride the shared renderer primitives.

*Tests*: golden — styled-text page (incl. underline + translucent color), shape-style page;
PDF parity — underline line present at the computed offset/width alongside existing
content-stream assertions.

## C12 — Localization & a11y (FR-016, SC-006)

All new labels, tooltips, "None", and "unavailable" texts come from
`JetPrintLocalizations` with en/de/tr entries. Toggles/segments/swatches carry semantic
button roles and localized labels; all controls keyboard-operable (panel's existing
conventions).

*Tests*: widget — labels resolve in all three locales; `accessibility_semantics_test.dart`
extended for the new control groups.

## C13 — Latency (SC-005)

A committed change repaints the canvas within 100 ms: commits are one synchronous
`_commit` + `notifyListeners`; the canvas repaints on `revision` change — no new async hops.
*Verified by construction + existing repaint tests; no dedicated perf harness.*
