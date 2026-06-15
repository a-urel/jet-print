# Label demo — 3-column address labels (design)

**Date:** 2026-06-16
**Status:** Approved (brainstorming)

## Goal

Add a playground sample that renders **3-column address labels** over **100
sample records** — an Avery-style A4 label sheet — filling the existing
`_comingSoon('etiket', …)` placeholder tab (the `tabLabel` l10n string already
exists in en/de/tr).

## Constraint that shapes the design

The engine flows `detail` bands **top-to-bottom only**. Native multi-column
flow (`BandType.columnHeader/columnFooter`, `PageFurniture.columnHeader`) is
*reserved but not implemented* — the layouter explicitly skips those slots. So
the engine cannot place three labels *across* a page and wrap down.

## Approach (chosen): pre-chunk into rows of 3

Rather than build native column flow (a much larger spec), the demo reshapes
the data so the existing engine produces a label sheet:

- The 100 flat address records are grouped into **rows of 3**.
- Each row becomes one master map with **prefix-namespaced fields per cell**:
  `c0Name/c0Street/c0City/c0Country`, `c1*`, `c2*` (12 fields total).
- The single `detail` band is **one label-row tall (98pt)** and holds **three
  column blocks** of `TextElement`s at fixed X offsets (0, 179, 358).
- The engine flows these rows down the page — **8 rows per A4 page** — yielding
  a true 3-across-then-wrap label sheet with **zero engine changes**.

100 records → 34 rows → ~5 pages.

### Page geometry

A4 portrait: 595.28×841.89pt, 28.35pt margins → **content area ≈ 538×785pt**.

- Columns: pitch ≈ 179pt (X = 0, 179, 358); each cell content ~170pt wide.
- Rows: 98pt tall × 8 = 784pt ≈ content height → 8 labels per page.

### Label content (per cell, vertical stack)

| Line | y | content | style |
|------|----|---------|-------|
| Name | 8  | `$F{cNName}`   | bold |
| Street | 28 | `$F{cNStreet}` | normal |
| Postal + City | 46 | `$F{cNCity}` | normal |
| Country | 64 | `$F{cNCountry}` | grey |

A light `ShapeElement(ShapeKind.rectangle, stroke-only)` border frames each
cell so labels read as cut tiles. Trailing empty cells (last row has 1 of 3
filled) simply omit their keys → blank columns (no border drawn for empties is
acceptable; border is data-blind and drawn for all three cell slots).

## Components (mirrors the invoice / nested-list sample trio)

1. **`apps/jet_print_playground/lib/label_sample.dart`**
   - `const JetDataSchema labelSchema` — 12 flat fields (`cNName`, `cNStreet`,
     `cNCity`, `cNCountry` for N=0,1,2).
   - `ReportDefinition labelSampleDefinition()` — furniture-free definition;
     root `DetailScope` with one `BandNode(Band(detail, height:98))` carrying
     the three column blocks (3 borders + 12 text elements).

2. **`apps/jet_print_playground/lib/rendered_label_example.dart`**
   - 100 deterministic synthetic addresses (cycling name/street/city/country
     arrays — no RNG, stable output).
   - `_chunkIntoRows()` — groups flat addresses by 3 into prefixed maps.
   - `JetDataSource labelDataSource()` over the chunked rows.
   - `RenderedReport renderLabelDefinition({definition, source, fonts})` via
     `JetReportEngine().renderDefinition`, defaulting to the sample.

3. **`apps/jet_print_playground/lib/main.dart`**
   - Replace `_comingSoon('etiket', …)` with a live `ShadTab` wired to
     `labelSampleDefinition()` / `labelSchema` / `renderLabelDefinition`.

## Tests (mirror nested-list)

- `label_definition_test.dart` — definition shape (root scope, single detail
  band, 12 text bindings, three borders) and `validate()` is empty.
- `rendered_label_example_test.dart` — clean render (no error diagnostics),
  page count > 0, and the data source carries 100 addresses in 34 rows.

## Out of scope (YAGNI)

- Native engine multi-column flow.
- Configurable label dimensions / Avery template picker.
- Real address data / localization of sample content.
