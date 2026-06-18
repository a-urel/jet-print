# Packing slip demo — single-shipment delivery note (design)

**Date:** 2026-06-19
**Status:** Approved (brainstorming)

## Goal

Replace the lone `_comingSoon('makbuz', …)` placeholder tab in the playground
([`apps/jet_print_playground/lib/main.dart`](../../../apps/jet_print_playground/lib/main.dart))
with a real, rich **packing slip / delivery note** demo — a single outbound
shipment with a two-column Ship-To/Bill-To header, a scannable tracking **QR
code**, items grouped into **boxes** with per-box subtotals, grand totals, and a
signature footer.

The demo combines more chrome than any existing tab while staying entirely on
the **public API** (`package:jet_print/jet_print.dart`) — no engine changes.

## Why this slot earns its place

Structurally a packing slip is Shipment ▸ Box ▸ Item, the **same 3-level
nesting path** the nested-list tab already proves works (so `validate()` passes
the same way). The *new* coverage is everything around that spine:

- A **two-column Ship-To / Bill-To** address header (side-by-side text blocks).
- A **QR tracking code** (`BarcodeSymbology.qrCode`) — distinct from the EAN-13
  barcode tab's 1D symbology.
- **Multi-measure roll-up:** two real leaf measures (`lineWeight`, `qtyShipped`)
  summed at box and grand level, plus a `COUNT` of boxes — versus the
  nested-list tab's single money measure.
- Item-level richness: **product attributes** and **lot numbers** per line.
- A **signature / received-by** footer printed once at the end.

## Constraints that shape the design

- **No two sibling per-row bands at master level.** `validate()` flags 2+
  independent per-row collections at the top as "not yet rendered." The slip
  models everything under one master shipment with nested `boxes` → `items`, so
  this never arises (mirrors the nested-list tab).
- **Fill cannot import the barcode encoder.** Barcode/QR symbols render through
  the same render-callback path the barcode tab uses; the QR encodes via the
  engine's render path, not at fill time. Mirror `barcode_sample.dart` exactly.
- **Per-box subtotal = items-scope footer.** A nested `DetailScope`'s footer
  folds its own rows (spec 029 same-scope path). The `items` scope resets per
  box, so its footer prints once per box → the per-box subtotal. Grand totals
  live on the shipment group footer via multi-level descent over `[boxes,
  items]` (spec 033).

## Data schema (`shipmentSchema`)

A single shipment (master) → `boxes` → `items`:

```
Shipment (master, one record):
  shipmentNo   string
  shipDate     dateTime
  orderNo      string
  carrier      string
  trackingNo   string        → bound to the QR code
  shipToName   string
  shipToAddress string       (multi-line)
  billToName   string
  billToAddress string       (multi-line)
  boxes[] (collection):
    boxNo       string
    dimensions  string        e.g. "40 × 30 × 25 cm"
    items[] (collection):
      sku         string
      description string
      attributes  string       e.g. "Size: L · Color: Navy"
      lotNo       string
      qtyShipped  integer      leaf measure → SUM = unit count
      lineWeight  double        leaf measure → SUM = weight (kg)
```

`qtyShipped` and `lineWeight` are the only stored measures; every subtotal and
total is computed live via inline aggregates (no stored totals), the way the
nested-list sample treats `lineTotal`.

## Report structure (`packingSlipDefinition()`)

Authored in the reified band model (spec 024), mirroring the nested-list
definition with richer bands.

- **`PageFurniture`** (record-blind): a slim "PACKING SLIP" running title; a
  "Page N of M" page footer.
- **`ReportBody.root`** — master `DetailScope` over the shipment, with the
  shipment as a `GroupLevel` keyed on `$F{shipmentNo}`:
  - **Group header (tall — the rich chrome):**
    - Ship-To block (left): `shipToName` bold + `shipToAddress`.
    - Bill-To block (right column, fixed X offset): `billToName` + `billToAddress`.
    - Order / date / carrier fields.
    - **QR `BarcodeElement`** top-right: `symbology: BarcodeSymbology.qrCode`,
      `dataField: 'trackingNo'`, with a valid literal fallback for the
      headless/no-row canvas (mirrors `barcode_sample.dart`).
  - **`boxes` `NestedScope`:**
    - Per-box **detail band**: "Box {boxNo} · {dimensions}" + item column titles.
    - **`items` `NestedScope`** → per-item **detail band**: sku · description ·
      attributes · lotNo · qtyShipped · lineWeight.
    - **`items`-scope footer = per-box subtotal**: `SUM($F{qtyShipped})` units,
      `SUM($F{lineWeight})` kg.
  - **Group footer = grand totals:** `COUNT($F{boxNo})` boxes,
    `SUM($F{qtyShipped})` units, `SUM($F{lineWeight})` kg (multi-level descent).
- **`ReportBody.summary`** — the record-blind **signature / received-by** band:
  a signature line, printed-name line, and date-received line, printed once at
  the end.

## Components (mirrors the invoice / nested-list / label sample trio)

1. **`apps/jet_print_playground/lib/packing_slip_sample.dart`**
   - `const JetDataSchema shipmentSchema` — the master/boxes/items shape above.
   - `ReportDefinition packingSlipDefinition()` — furniture + grouped root +
     nested `boxes`/`items` + summary, per the structure above.

2. **`apps/jet_print_playground/lib/rendered_packing_slip_example.dart`**
   - One deterministic sample shipment: ~3 boxes, 2–4 items each, with realistic
     SKUs, attributes, and lot numbers (no RNG — stable output).
   - `JetDataSource packingSlipDataSource()` over the single shipment record.
   - `RenderedReport renderPackingSlipDefinition({definition, source, fonts})`
     via the engine's `renderDefinition` path, defaulting to the sample.

3. **`apps/jet_print_playground/lib/main.dart`**
   - Replace `_comingSoon('makbuz', l10n.tabReceipt, LucideIcons.receipt)` with
     a live `ShadTab` `_DesignerTab` wired to `packingSlipDefinition()` /
     `shipmentSchema` / `renderPackingSlipDefinition`, with a package icon
     (`LucideIcons.package`) and the packing-slip label.

4. **`apps/jet_print_playground/lib/l10n/app_localizations*.dart`** (en/de/tr)
   - Replace the now-unused `tabReceipt` string with `tabPackingSlip`
     (en "Packing slip", de "Lieferschein", tr "İrsaliye").

## Tests (mirror nested-list / label)

- **`packing_slip_definition_test.dart`** — definition shape (grouped root
  keyed on `shipmentNo`, nested `boxes`/`items` scopes, the QR `BarcodeElement`
  bound to `trackingNo`, per-box footer + grand-total footer + summary band) and
  `validate()` is empty.
- **`rendered_packing_slip_example_test.dart`** — clean render (no error
  diagnostics), page count > 0, and the sample carries the expected box/item
  counts; live subtotals/totals match the summed sample data.

## Out of scope (YAGNI)

- Batch of multiple shipments (one slip per page) — single shipment only.
- Conditional formatting (e.g. backorder highlighting) / qty-ordered-vs-shipped.
- A separate per-item attributes *collection* — attributes are a single string
  field per line, not a nested list.
- Real carrier integration or live tracking; the QR encodes the sample tracking
  number only.
- Localization of the sample data (only the designer chrome and tab label are
  localized).
