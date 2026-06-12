# Phase 0 Research: Editable Paper Type & Margins

All four spec clarifications were already resolved in the spec (paper presets = A4/A3/A5/Letter/Legal +
Custom; margins = presets **and** per-side; out-of-range → clamp; units = pt only). The open *planning*
unknowns were the concrete preset numbers, the recognition tolerance, the clamp rule, the shape of the
controller op, and the Office-style preview. Each is grounded in an existing codebase precedent below.

---

## D1 — Paper-size preset values (logical points)

**Decision**: Standard sizes as plain constants in a private `paper_presets.dart`, stored **portrait**
(width ≤ height); recognition matches either orientation.

| Name | Width (pt) | Height (pt) | Source |
|------|-----------|------------|--------|
| A4 | 595.28 | 841.89 | matches existing `PageFormat.a4Portrait` |
| A3 | 841.89 | 1190.55 | ISO 216 (2× A4 short side) |
| A5 | 419.53 | 595.28 | ISO 216 |
| Letter | 612.0 | 792.0 | ANSI (8.5″ × 11″ × 72) |
| Legal | 612.0 | 1008.0 | ANSI (8.5″ × 14″ × 72) |

**Rationale**: A4 already exists at exactly these numbers
([`page_format.dart:25`](../../packages/jet_print/lib/src/domain/page_format.dart#L25)); keeping the same
unit (pt) honors FR-014 (no mm/inch). A3/A5 derive from ISO 216; Letter/Legal from 72 pt-per-inch — the same
basis the PDF exporter uses. Names (A4, Letter…) are **not localized** (they are universal standards); only
"Custom", "Portrait/Landscape", and the margin-preset names are localized (FR-012).

**Alternatives considered**: Adding each as a `static const` on `PageFormat` (domain) — rejected: it pushes
a UI-facing catalog into the domain and breaks the `format_presets.dart` precedent of keeping preset lookups
in the designer seam. Sourcing from the `pdf` package's `PdfPageFormat` — rejected: couples the model catalog
to a render dependency and risks unit drift.

---

## D2 — Margin presets

**Decision**: Four presets in a private `margin_presets.dart`, applied to all four sides equally; localized
names.

| Preset | Per-side (pt) | Note |
|--------|--------------|------|
| Normal | 28.35 | the current default (~1 cm), = `JetEdgeInsets.all(28.35)` |
| Narrow | 14.17 | ~0.5 cm |
| Wide | 56.69 | ~2 cm |
| None | 0 | flush to edge |

**Rationale**: "Normal = current default" keeps existing templates reading as **Normal**, not Custom
(spec Assumptions). Narrow/Wide are the round half/double of Normal — exact values were explicitly left to
planning. A chosen preset writes all four sides at once (FR-005); editing any side afterward yields uneven
insets that recognition reports as **Custom**.

**Alternatives considered**: Office's inch-based values (0.5″/1″/2″) — rejected: this app's baseline is the
metric ~1 cm default, so anchoring "Normal" to it avoids reclassifying every existing report.

---

## D3 — Preset recognition (size & margin) and "Custom"

**Decision**: Pure functions `recognizePaper(PageFormat) → {name, orientation} | Custom` and
`recognizeMargin(JetEdgeInsets) → preset | Custom`, matching with a small epsilon (`1e-2 pt`) and in
**either orientation** (compare the page's sorted {short, long} sides to the preset's). Recognition affects
**display only** — it never rewrites dimensions (FR-003).

**Rationale**: Directly mirrors `FormatPreset` (013), where preset identity is computed for the UI and never
persisted. The epsilon absorbs the rounded display (panel shows `595`, model holds `595.28`) so a rounded
A4 still names "A4" (edge case in spec). Sorting sides makes recognition orientation-agnostic, satisfying
FR-002 ("matching preset name … in either orientation").

**Alternatives considered**: Exact `==` match — rejected: floating-point dimensions and rounded entry would
mislabel A4 as Custom. Storing a `presetId` on the model — rejected: violates V (new field/schema) and the
"derived, not stored" rule.

---

## D4 — Validation = clamp, in one place

**Decision**: A private `clampPageFormat(PageFormat) → PageFormat` enforcing `kMinPageSide` (each of
width/height ≥ a small minimum, e.g. 1 pt) and a **positive content area** — `left+right ≤ width −
kMinContentExtent` and `top+bottom ≤ height − kMinContentExtent`; offending side(s)/dimension(s) are pulled
to the nearest valid value. `setPageFormat` clamps **before** `_commit`.

**Rationale**: FR-009 / SC-006 require silent correction, never a blocking error or unusable page. Centralizing
the clamp in the controller (one entry point) means every path — preset, orientation, custom W/H, per-side —
is validated identically, the same way `setBandHeight` floor-clamps to `kMinBandHeight`
([`controller:594`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L594))
and `setGeometry` clamps to the band. Empty/non-numeric **field** entries are handled at the widget (revert to
last valid, like `_NumberField` already does) so the controller only ever sees numbers.

**Alternatives considered**: Validating inside the command's `apply()` — rejected: commands stay pure
transforms (`SetFormatCommand` precedent); clamping is an input-conditioning concern that belongs with the
controller op so undo restores the exact prior page.

---

## D5 — One controller op: `setPageFormat(PageFormat)`

**Decision**: A single public mutator `void setPageFormat(PageFormat format)` → `clampPageFormat` →
`_commit(SetPageFormatCommand(format))`. The panel composes the next value with `copyWith` (or a preset) and
hands over the whole `PageFormat`.

**Rationale**: A page edit is one change to one immutable value object. One op keeps the public surface minimal
(I) — like 017 adding only `rename` — gives one undo step per edit (FR-007) by construction, and puts clamp +
no-op detection in one place (`_commit` already drops an identical-template change,
[`controller:959`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L959)).
`copyWith` on `PageFormat`/`JetEdgeInsets` (currently absent) is the one enabling domain change so the panel
can express "change only this side" / "swap W/H" without naming every field.

**Alternatives considered**: Granular `setPaperType`/`setOrientation`/`setMargin` setters — rejected: 3–4×
the public surface for no behavioral gain, and each would still build a full `PageFormat` internally.

---

## D6 — Orientation is derived, toggling swaps W/H

**Decision**: Orientation is a **view** (`portrait` iff `height ≥ width`), not a stored field. The toggle
builds `current.copyWith(width: height, height: width)` and calls `setPageFormat`. Applies to preset **and**
custom sizes (spec edge case).

**Rationale**: Storing orientation would be redundant with width/height and would need a schema field
(violating V). Deriving it keeps recognition and rendering reading one source. Swapping is a pure `copyWith`.

---

## D7 — Office-style page-preview sample (user request)

**Decision**: A private `_PagePreview` `CustomPaint` in the PAGE section: a sheet rectangle scaled to fit the
panel column at the page's true aspect ratio, with four inset guide lines drawn at the margin proportions —
re-rendered from the live `PageFormat` on every change. A schematic indicator, à la Microsoft Office print
settings.

**Rationale**: Gives the at-a-glance "what will the page look like" feedback Office users expect, reinforcing
the numeric controls. It is **designer chrome**, not a renderer: WYSIWYG (IV) is guaranteed by canvas/preview/
export sharing `template.page`, so the preview thumbnail carries no fidelity contract and needs no report
golden — a widget test asserting it reflects size/orientation/margins is sufficient.

**Alternatives considered**: Embedding a live mini render of page 1 — rejected: heavier, would couple the
inspector to the render pipeline, and overkill for a proportion indicator. A static portrait/landscape icon —
rejected: doesn't convey margins, which the user explicitly wants visible.

---

## D8 — Zero serialization / render-path impact

**Decision**: No codec change. `PageFormat{width,height,margins}` already serializes
([`page_format.dart:41`](../../packages/jet_print/lib/src/domain/page_format.dart#L41)); `kReportSchemaVersion`
stays **1**. All three render paths already read `template.page`
([`design_time_layout`](../../packages/jet_print/lib/src/designer/canvas/design_time_layout.dart#L34),
[`page_frame`](../../packages/jet_print/lib/src/rendering/frame/page_frame.dart#L15),
[`page_rasterizer`](../../packages/jet_print/lib/src/rendering/paint/page_rasterizer.dart#L39)), so one
`notifyListeners()` propagates a page change to canvas, preview, and export with no fork.

**Rationale**: Satisfies V (old templates load unchanged, edited page round-trips losslessly) and IV
(single render source) for free — the same "don't fork the pipeline" posture the 017 plan took. New goldens
are added only for a deliberately non-default page (Letter/landscape) to *prove* propagation; the default-A4
report goldens do not move because the default template is unchanged.
