# Phase 1 Data Model: Editable Paper Type & Margins

No persisted schema changes. This feature adds **derived** view-data (preset names, orientation), one
**command**, additive `copyWith` on two existing immutable value types, and two designer-layer preset tables.
`kReportSchemaVersion` stays **1**.

---

## Existing entities (unchanged on disk)

### `PageFormat` — domain, serialized inside `ReportTemplate.page`
[`page_format.dart`](../../packages/jet_print/lib/src/domain/page_format.dart)

| Field | Type | Unit | Serialized |
|-------|------|------|-----------|
| `width` | `double` | pt | yes (`'width'`) |
| `height` | `double` | pt | yes (`'height'`) |
| `margins` | `JetEdgeInsets` | pt | yes (`'margins'`) |

**Additive change**: a `copyWith({double? width, double? height, JetEdgeInsets? margins})` returning a new
`PageFormat`. No new field; `toJson`/`fromJson` unchanged.

### `JetEdgeInsets` — domain, the four-side margins
[`geometry.dart:68`](../../packages/jet_print/lib/src/domain/geometry.dart#L68)

| Field | Type | JSON key |
|-------|------|----------|
| `left` / `top` / `right` / `bottom` | `double` | `l` / `t` / `r` / `b` |

**Additive change**: a `copyWith({double? left, double? top, double? right, double? bottom})` so the panel can
edit one side without naming the others. No new field.

---

## New command

### `SetPageFormatCommand` — designer, `controller/commands/set_page_format_command.dart`
Mirrors [`SetFormatCommand`](../../packages/jet_print/lib/src/designer/controller/commands/set_format_command.dart)
(a pure transform).

| Member | Type | Purpose |
|--------|------|---------|
| `format` | `PageFormat` | the new (already-clamped) page |
| `label` | `String` | `'Change page'` (history label) |
| `apply(before)` | `DesignerDocument` | `identical`/equal page → return `before` (no-op); else `before.withTemplate(before.template.copyWith(page: format))` |

**Invariant**: `apply` is pure and total; it does **not** clamp (the controller clamps the input) and does
**not** move elements — `copyWith(page:)` leaves `bands`/elements untouched, so top-left anchors are preserved
(FR-013). Undo restores the exact prior `PageFormat`.

---

## New controller operation

### `JetReportDesignerController.setPageFormat(PageFormat format)`
[`jet_report_designer_controller.dart`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart)

```
setPageFormat(format):
  clamped = clampPageFormat(format)        # D4 — min side + positive content area
  _commit(SetPageFormatCommand(clamped))   # one undo step; no-op if equal to current page
```

One public method, undoable, notifying — the `setBandHeight`/`rename` idiom. Returns void (callers don't need
the changed bit).

---

## New private helpers (designer seam)

### `clampPageFormat(PageFormat) → PageFormat` — `controller/page_format_clamp.dart`
Constants `kMinPageSide` (e.g. `1.0`) and `kMinContentExtent` (e.g. `1.0`). Pulls width/height up to
`kMinPageSide`; if `left+right > width − kMinContentExtent`, scales/caps the offending side(s) to the nearest
value that leaves `kMinContentExtent` of content; same for top/bottom. Idempotent (clamping a valid page
returns it unchanged).

### Paper presets — `paper_presets.dart`

| Symbol | Shape |
|--------|-------|
| `kPaperPresets` | ordered `List<PaperPreset>` — `{name, portraitWidth, portraitHeight}` for A4, A3, A5, Letter, Legal (values per research D1) |
| `recognizePaper(PageFormat) → PaperMatch` | `{presetName?: String, isCustom: bool}` — sorts the page's sides, matches a preset within `1e-2` in either orientation, else `isCustom: true` |
| `applyPaper(PaperPreset, {landscape}) → PageFormat` helper | builds a `PageFormat` at the preset size (swapping W/H for landscape), preserving current margins |

### Margin presets — `margin_presets.dart`

| Symbol | Shape |
|--------|-------|
| `kMarginPresets` | ordered `List<MarginPreset>` — `{kind, value}` for Normal/Narrow/Wide/None (research D2); labels via l10n |
| `recognizeMargin(JetEdgeInsets) → MarginMatch` | `{presetKind?, isCustom}` — four equal sides matching a preset value (within `1e-2`) → that preset; uneven or unmatched → `isCustom` |

### Orientation (derived, no type stored)
`portrait` iff `height ≥ width`. Toggle = `current.copyWith(width: height, height: width)`.

---

## Recognition truth table (display only — never rewrites the model)

| Current page | `recognizePaper` shows | `recognizeMargin` shows |
|--------------|------------------------|--------------------------|
| 595.28 × 841.89, all 28.35 | **A4**, Portrait | **Normal** |
| 841.89 × 595.28, all 14.17 | **A4**, Landscape | **Narrow** |
| 612 × 792, all 0 | **Letter**, Portrait | **None** |
| 595 × 842 (rounded), all 28 | **A4** (ε-tolerant) | **Normal** (ε-tolerant) |
| 500 × 700, all 28.35 | **Custom** | **Normal** |
| 595.28 × 841.89, L20/T28.35/R28.35/B28.35 | **A4** | **Custom** |

---

## Public API delta (recorded in `public_api_test`)

| Symbol | Kind | Status |
|--------|------|--------|
| `JetReportDesignerController.setPageFormat(PageFormat)` | method | **new** |
| `PageFormat.copyWith(...)` | method | **new** |
| `JetEdgeInsets.copyWith(...)` | method | **new** |
| `SetPageFormatCommand`, `clampPageFormat`, `*Preset`, `recognize*`, `_PagePreview` | — | **private** (not exported) |

No removals, no signature changes, no schema/codec change.
