# Phase 1 Contracts: Grid & Snap Helper Tools

Behavioral contracts and their test groups. "Contract" here means an observable guarantee a test
pins — there is no external API surface (the package adds no public symbols). Each contract maps to
functional requirements (FR-xxx) and success criteria (SC-xxx) from [spec.md](../spec.md). Per
Constitution III, the pure-helper contracts are written and failing **before** implementation.

---

## C1 — `gridLineOffsets` enumerates snap-coincident lines (pure)

**Test group**: `test/designer/canvas/grid_geometry_test.dart` (unit)

| # | Given | Then | Refs |
|---|-------|------|------|
| C1.1 | `extent = 100`, `step = kGridStep`, generous `scale`, small `minGapPx` | returns `0, step, 2·step, …` ascending, all `≤ 100`; every value is an exact multiple of `step` (snap-coincident) | FR-002, SC-003 |
| C1.2 | `scale` so `step·scale` just **below** `minGapPx` | coarsens to `step·f` (smallest integer `f` with `step·f·scale ≥ minGapPx`); result still multiples of `step` | FR-006, SC-006 |
| C1.3 | very small `scale` (extreme zoom-out, `⌈minGapPx/(step·scale)⌉ > kGridMaxCoarsenFactor`) | returns `[]` (grid hidden) — never a dense fill | FR-006, SC-006 |
| C1.4 | `extent` not a whole multiple of `step` | last line is the greatest multiple `≤ extent`; nothing drawn beyond `extent` | FR-007 |
| C1.5 | `extent = 0` (degenerate band) | returns `[]` or `[0]` only; no negative/over-extent offsets | edge case |

---

## C2 — Grid visibility & placement (widget)

**Test group**: `test/designer/canvas/grid_test.dart`

| # | Given | Then | Refs |
|---|-------|------|------|
| C2.1 | `gridEnabled == true` | a grid is painted over the page content area | FR-001, FR-002, SC-001 |
| C2.2 | `gridEnabled == false` | no grid is painted (painter absent from the stack) | FR-004, SC-001 |
| C2.3 | grid on, with elements present | the grid paints **behind** band separators, elements, and the selection overlay (backmost) — element pixels are unobscured | FR-003 |
| C2.4 | a report with ≥ 2 bands of heights not multiples of 5 mm | grid lines restart at each band's top (per-band origin) and coincide with that band's snap targets | FR-002 (D1) |
| C2.5 | default controller (no preference touched) | grid is on (default) and the top-bar grid button reflects active | FR-014, SC-007 |

---

## C3 — Grid alignment under zoom & pan (widget)

**Test group**: `test/designer/canvas/grid_alignment_test.dart` (mirrors `ruler_alignment_test.dart`)

| # | Given | Then | Refs |
|---|-------|------|------|
| C3.1 | grid on, zoom at min / 100 % / max | a chosen page position maps to the same grid line at every zoom (scales with the page) | FR-005, SC-002 |
| C3.2 | grid on, canvas scrolled | the grid scrolls with the page, staying registered | FR-005, SC-002 |
| C3.3 | grid on, zoom far out | grid thins/hides (via C1.2/C1.3) — page is not a solid fill | FR-006, SC-006 |

---

## C4 — Snap to the 5 mm grid, governed by the snap tool only (behavior)

**Test groups**: `test/designer/canvas/snapping_test.dart`,
`test/designer/canvas/resize_snap_test.dart` (**updated** for the 5 mm step + decoupling),
`test/designer/controller/move_commit_teardown_test.dart` (**updated**)

| # | Given | Then | Refs |
|---|-------|------|------|
| C4.1 | snap on, drag an edge within threshold of a 5 mm grid line | the edge commits exactly on `k·kGridStep`; a guide is shown during the drag | FR-009, FR-012, SC-003 |
| C4.2 | snap on, resize an edge near a 5 mm grid line | the resized edge snaps to `k·kGridStep` on commit | FR-009, SC-003 |
| C4.3 | snap **off** | no snapping; element follows the pointer freely | FR-011, SC-004 |
| C4.4 | snap **on**, grid **hidden** (`gridEnabled == false`) | element **still** snaps to grid lines (and siblings/bands) — snapping is independent of visibility | FR-010 (D3), US2.4 |
| C4.5 | snap on, snap-bypass modifier held during the drag | snapping suspended for that drag; toggle states unchanged | FR-013, US2.5 |
| C4.6 | pure `snapMove`/`snapResize` with `grid: true` vs `grid: false` | grid candidates included/excluded respectively (helper-level flag retained) | FR-009 |

> **Migration note**: existing assertions that `setGridEnabled(false)` disables grid snapping are
> **inverted** by C4.4 and must be re-expressed via `setSnapEnabled(false)` / `bypassSnap`. Expected
> snapped coordinates change from multiples of `8` to multiples of `kGridStep (≈14.173)`.

---

## C5 — Toggles independent; state not serialized (behavior)

**Test groups**: `test/designer/top_bar_test.dart`,
`test/designer/controller/rulers_visibility_test.dart` (existing, verify still green)

| # | Given | Then | Refs |
|---|-------|------|------|
| C5.1 | tap the grid button | `controller.gridEnabled` flips; `snapEnabled` unchanged; button reflects active | FR-001, FR-010 |
| C5.2 | tap the snap button | `controller.snapEnabled` flips; `gridEnabled` unchanged; button reflects active | FR-008, FR-010 |
| C5.3 | change grid/snap, then serialize + reload the template | round-trips byte-identically; grid/snap state absent from the document; render identical | FR-015, SC-005 |

---

## C6 — Grid absent from preview/export/print (WYSIWYG)

**Test group**: existing preview/export goldens + `public_api_test` / architecture tests (verify
unchanged)

| # | Given | Then | Refs |
|---|-------|------|------|
| C6.1 | grid visible on the canvas, then open preview / export | output contains no grid; existing invoice preview/export goldens **unchanged** | FR-016, SC-005 (Principle IV) |
| C6.2 | architecture/public-API tests | `grid_geometry.dart` imports no Flutter/domain/render; no new exported symbol | Principle I, II |

---

## Coverage summary

| Requirement | Pinned by |
|-------------|-----------|
| FR-001 visible-grid toggle | C2.1, C5.1 |
| FR-002 5 mm grid, snap-coincident, per-band | C1.1, C2.1, C2.4 |
| FR-003 backmost, non-obscuring | C2.3 |
| FR-004 off → nothing drawn | C2.2 |
| FR-005 zoom/pan registration | C3.1, C3.2 |
| FR-006 adaptive density | C1.2, C1.3, C3.3 |
| FR-007 clipped to content/band | C1.4 |
| FR-008 snap toggle | C5.2 |
| FR-009 snap to grid (move/resize) | C4.1, C4.2 |
| FR-010 decoupled / independent | C4.4, C5.1, C5.2 |
| FR-011 snap off → free | C4.3 |
| FR-012 snap guide | C4.1 |
| FR-013 bypass modifier | C4.5 |
| FR-014 default on | C2.5 |
| FR-015 not serialized | C5.3 |
| FR-016 not in output | C6.1 |
| FR-017 localized tooltips | existing top-bar/localization tests (reused, unchanged) |
