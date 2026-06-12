# Contract: Editable Page Properties (PAGE section)

Behavioral contracts for the rebuilt PAGE section and `setPageFormat`. Each row is pinned by a test; the test
group is named in the last column. Tests are written **first** (red) per Principle III.

## C1 — Paper type (US1, FR-001/002/003)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C1.1 | page is A4 | PAGE section opens | paper-type control shows **"A4"** (by name, not raw numbers) | `properties_editor` |
| C1.2 | paper-type picker | select **Letter** | page becomes 612 × 792; canvas re-renders at the new size; margins unchanged | `properties_editor` |
| C1.3 | page matches no preset (500 × 700) | PAGE section opens | control shows **"Custom"**, dimensions unaltered | `paper_presets` + `properties_editor` |
| C1.4 | rounded A4 (595 × 842) | recognize | still named **"A4"** (ε-tolerant) | `paper_presets` |
| C1.5 | A4 portrait vs A4 landscape | recognize each | both named **"A4"** (either orientation) | `paper_presets` |

## C2 — Margins (US2, FR-004/005)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C2.1 | PAGE section | choose margin preset **Narrow** | all four sides = 14.17; content area updates | `properties_editor` |
| C2.2 | margins all 28.35 | set **left** to 50 | only left changes; preset label becomes **Custom**; others stay 28.35 | `properties_editor` + `margin_presets` |
| C2.3 | four equal sides = a preset value | recognize | shows that preset; uneven sides → **Custom** | `margin_presets` |
| C2.4 | a margin field | type empty / non-numeric, blur | reverts to last valid value (no blank applied) | `properties_editor` |

## C3 — Orientation & custom (US3, FR-010/011)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C3.1 | A4 portrait | toggle to **Landscape** | width/height swap (841.89 × 595.28); canvas re-renders | `properties_editor` + `set_page_format_command` |
| C3.2 | paper type = **Custom** | enter W = 300, H = 500 | page adopts exactly 300 × 500 | `properties_editor` |
| C3.3 | paper type ≠ Custom | — | Custom W/H fields are hidden/disabled | `properties_editor` |
| C3.4 | custom W or H at/below minimum | confirm | clamped to a valid minimum (no zero/negative page) | `set_page_format_command` |
| C3.5 | a custom W or H field | type empty / non-numeric, blur | reverts to last valid value (no blank/zero applied) | `properties_editor` |

## C4 — Clamp / usable page (FR-009, SC-006)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C4.1 | width 200, set left+right that exceed it | apply | offending side(s) clamped so a positive content area remains | `set_page_format_command` |
| C4.2 | any valid page | clamp | returned unchanged (idempotent) | `set_page_format_command` |
| C4.3 | margins exactly consuming the page | apply | corrected to leave `kMinContentExtent` of content | `set_page_format_command` |

## C5 — Undo / redo (FR-007, SC-004)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C5.1 | any page change (size/orientation/margin) | undo | reverts in a **single** step to the exact prior `PageFormat`; `canUndo` was true | `set_page_format_command` |
| C5.2 | after undo | redo | re-applies the same change | `set_page_format_command` |
| C5.3 | `setPageFormat` with the current page | commit | no-op: nothing pushed to history, no notify | `set_page_format_command` |

## C6 — Persistence & back-compat (FR-008, SC-005)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C6.1 | edited page (Letter, Narrow, landscape) | encode → decode | round-trips losslessly | `set_page_format_command` (codec) |
| C6.2 | a pre-feature template | load | opens unchanged; `kReportSchemaVersion` still 1 | existing `report_codec` suite |

## C7 — WYSIWYG propagation (FR-006, SC-003)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C7.1 | a Letter / landscape page | render canvas, preview, export | all three show the same size + content area | `goldens` (new `page_letter_landscape_*`) |
| C7.2 | default A4 report | render | existing report goldens **unchanged** (byte-identical) | existing `goldens` |

## C8 — Content preservation (FR-013)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C8.1 | elements at known band-relative positions | change to a smaller page | elements keep their top-left anchors (not repositioned/deleted) | `set_page_format_command` |

## C9 — Office-style preview & availability (user request, FR-012, Assumptions)

| # | Given | When | Then | Test group |
|---|-------|------|------|-----------|
| C9.1 | PAGE section | render `_PagePreview` | shows a sheet at the page's aspect ratio with margin guide lines | `properties_editor` |
| C9.2 | toggle orientation | — | the preview’s aspect flips portrait↔landscape | `properties_editor` |
| C9.3 | change a margin | — | the preview’s guide insets update proportionally | `properties_editor` |
| C9.4 | no element selected | open Properties | PAGE controls are present and editable (report-level) | `properties_editor` |
| C9.5 | locale en / de / tr | render | all new labels (paper, orientation, margin presets) localized | `properties_editor` |

---

### Invariants (must hold across all of the above)
1. The model is **never** mutated by recognition or by the preview — only `setPageFormat` changes the page.
2. Every produced page has a **positive** content area (clamp guarantees it).
3. Each Properties edit is **exactly one** undo step.
4. Orientation and preset names are **derived**, never serialized; no schema field is added.
5. Canvas, preview, and export read the same `template.page` — no parallel render path.
