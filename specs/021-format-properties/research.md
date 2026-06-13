# Research: Format Properties — Font & Color Editors

**Feature**: `021-format-properties` | **Date**: 2026-06-13
**Input**: [spec.md](spec.md) · codebase exploration of `packages/jet_print`

No NEEDS CLARIFICATION markers remained in the Technical Context; the spec carries three
recorded clarifications (bold-toggle-only, underline included, Properties-panel-only). The
decisions below resolve every design unknown the spec leaves to the plan.

---

## 1. Where the font family list comes from

**Decision**: The family picker enumerates the **designer's own `FontRegistry`** via a new
internal `families` getter (registered family names, always including the bundled default
`JetSans`). The registry instance is hoisted from `DesignCanvas` (which today constructs
`DesignTimeFrameBuilder()` privately at `design_canvas.dart:91`) into the designer state, so
the canvas frame builder and the Properties panel share one instance. The selected element's
stored `fontFamily`, when not registered, is appended to the picker marked **unavailable**
(edge case: template authored elsewhere) — choosing any other family overwrites it; leaving
it untouched preserves it byte-for-byte.

**Rationale**: FR-001 scopes the picker to "the set of fonts available to the report
(including the built-in default)", and the spec's Assumptions explicitly exclude font
discovery/management. Critically, opening a *public* host-registration seam only in the
designer would violate Constitution IV: `JetReportEngine.render` (measurement),
`JetReportPreview` (`jet_report_preview.dart:120`), and `JetReportExporter`
(`jet_report_exporter.dart:43,76`) each construct their own default-only registry, so a
host-registered family would style the canvas but fall back to `JetSans` in preview/export —
silent WYSIWYG divergence. Because every path today resolves the identical (default-only)
family set, fidelity holds by construction. When a host-font seam lands as its own
cross-cutting spec (one registry threaded through designer + engine + preview + exporter
public API), this picker grows automatically — its architecture (enumerate registry, flag
stored-but-unregistered) is already the right one.

**Alternatives considered**:
- *Thread a public `FontRegistry` through designer/engine/preview/exporter now* — rejected:
  a public-API expansion across four entry points with its own determinism, lifecycle, and
  documentation questions; none of this feature's FRs require it, and it would dwarf the
  editor work this spec is about.
- *List OS/Flutter-bundled fonts on the canvas* — rejected: PDF export embeds TTF bytes from
  the registry; families without registered bytes cannot be embedded, breaking SC-002.

## 2. Underline end-to-end (the one net-new attribute)

**Decision**: `JetTextStyle` gains `bool underline` (default `false`, serialized only when
`true`). `TextRunPrimitive` already carries the whole `JetTextStyle` (`primitive.dart:28-63`),
so the primitive layer is untouched. Both painters draw the underline as an **explicit stroked
line** — *not* `ui.TextDecoration.underline` — using one shared geometry helper in
`rendering/text/` (`underlineFor(fontSize) → (offset, thickness)` — each painter applies it
at its own baseline and measured line width;
conventional em-fractions: offset ≈ 0.11 em below baseline, thickness ≈ 0.06 em). Each painter
applies it inside its existing per-line alignment math (`canvas_painter.dart:87-90`,
`pdf_painter.dart:119-124`), where the line's `dx` and width are already known.

**Rationale**: WYSIWYG (IV). Skia computes its own underline placement from font tables the
PDF backend does not read; letting the canvas use `TextDecoration` while the PDF painter
draws a manual line guarantees drift. One shared helper consumed by both painters makes the
geometry identical by construction — the same "one geometry source" pattern `shapePath`
proved in 020. Pinned by a parity test (the `pdf_painter_parity_test.dart` pattern) plus a
golden.

**Alternatives considered**:
- *`ui.TextDecoration.underline` on canvas + manual line in PDF* — rejected: two placement
  algorithms, unverifiable parity.
- *Emit a `LinePrimitive` per underlined line from `TextElementRenderer`* — rejected: the
  per-line alignment `dx` is computed in the painters; the renderer would have to duplicate
  that alignment math, creating a third copy that can drift.
- *Parse the TTF `post` table for true underline metrics* — rejected for now: the metrics
  parser reads `head/hhea/maxp/hmtx/cmap` only; em-fraction constants are visually standard,
  deterministic, and identical across painters. Revisit only if fidelity issues are observed.

## 3. Bold toggle over a four-value weight enum

**Decision** (per spec clarification): the Bold toggle reads **active iff
`weight == JetFontWeight.bold`**. `medium`/`semiBold` display the toggle inactive and are
preserved untouched; the first press while inactive commits `bold`, a press while active
commits `normal`. No UI for intermediate weights.

**Rationale**: locked by the 2026-06-13 clarification; intermediate weights remain reachable
programmatically and render/serialize as today (FR-003, FR-006).

## 4. Color editor: hand-rolled on shadcn primitives, no new dependency

**Decision**: one private reusable `_ColorField` built from existing primitives —
`ShadPopover` anchored to a trigger showing the current swatch + hex code, containing a fixed
palette grid (~16 opaque swatches), a hex `ShadInput`, and (only where the property is
optional) a **None** entry. Font-family select uses `ShadSelect` (present in
`shadcn_ui 0.54.0`: `select.dart`); B/I/U and alignment are hand-rolled toggle/segment groups
following the panel's existing `_OrientationToggle` precedent (`properties_panel.dart:1094`)
with lucide icons.

**Rationale**: `shadcn_ui 0.54.0` ships no color picker, toggle-group, or segmented control;
the panel already hand-rolls exactly this kind of control. A third-party picker package would
add a dependency (Constitution: dependencies minimal/justified) for gradient/HSV depth the
spec explicitly scopes out ("swatch palette plus hex entry is sufficient for v1").

**Alternatives considered**: `flutter_colorpicker` / `flex_color_picker` — rejected: new
dependency, foreign visual language inside a shadcn panel, capabilities beyond v1 scope.

## 5. Alpha preservation rule (FR-010 / transparency edge case)

**Decision**: the editor displays hex as `#RRGGBB` when alpha is `FF`, `#AARRGGBB` otherwise.
A **6-digit** typed value and a **palette swatch pick** replace RGB but preserve the stored
alpha; an **8-digit** typed value sets alpha explicitly. Malformed input (regex
`^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$` fails) is rejected: the field restores the last valid
value and gives visual feedback (destructive-color flash, the panel's existing invalid-input
convention).

**Rationale**: satisfies "preserve any alpha component already stored" without forcing every
user through 8-digit entry; a swatch pick changing *hue* shouldn't silently discard a
template's deliberate translucency.

## 6. "None" fill/stroke and stroke width 0

**Decision**: `JetBoxStyle.fill`/`stroke` already model "none" as `null` (`box_style.dart`).
The color editor's None entry commits `null`. For FR-008's "width zero removes the outline":
the stored `stroke` color is **kept**, and `ShapeElementRenderer.emit` passes
`stroke: strokeWidth > 0 ? style.stroke : null` — one renderer seam, zero painter changes,
parity across canvas/preview/export by construction. Stepping the width back above 0 restores
the outline with its remembered color.

**Alternatives considered**: *commit `stroke: null` when width hits 0* — rejected: destroys
the user's color choice, making width-0 a trapdoor; *guard in each painter* — rejected: two
copies of the rule.

## 7. Controller surface: one mutator per style domain

**Decision**: three public controller ops, each one undoable `_commit` step —
`setTextStyle(String id, JetTextStyle style)` (`SetTextStyleCommand`),
`setShapeStyle(String id, JetBoxStyle style)` (`SetShapeStyleCommand`),
`setBarcodeColor(String id, JetColor color)` (`SetBarcodeColorCommand`). Editors construct
the next style via new `copyWith` on `JetTextStyle`/`JetBoxStyle` (sentinel-based for the
nullable `fontFamily`/`fill`/`stroke` so "set to null" is expressible) and commit whole
values. Commands return `before` unchanged on no-ops so `_commit`
(`jet_report_designer_controller.dart:986`) records no history.

**Rationale**: mirrors the established one-conceptual-edit-one-method pattern (`setText`,
`setFormat`, `setShapeKind`); keeps the public surface at three methods instead of ~10
per-attribute ones (Principle I) while still yielding exactly one undo step per committed
editor change (FR-013) — each editor commit is one `copyWith` + one `_commit`.

**Alternatives considered**: *per-attribute methods* (`setFontSize`, `setBold`, …) — rejected:
public surface ×7 with identical semantics; *generic `setProperty(id, key, value)`* —
rejected: stringly-typed, unanalyzable, breaks exhaustive testing.

## 8. Barcode color visibility on a placeholder renderer

**Decision**: `BarcodeElementRenderer` is placeholder-only (real symbology is a later spec).
This feature binds the editor to `BarcodeElement.color` (model + persistence, FR-011) and
makes the placeholder consume `el.color` for its glyph/border tint, so a color change is
visibly reflected on canvas, preview, and export (shared renderer ⇒ parity). When real bar
rendering lands, it inherits the already-edited color.

**Rationale**: Story 3's acceptance ("bars re-render in that color") can only be honored to
the extent bars render at all; tinting the placeholder keeps the editor honest (visible,
WYSIWYG-consistent feedback) without pulling symbology rendering into scope.

## 9. Serialization: additive fields, schema stays 1

**Decision**: `underline` is written only when `true`; absent ⇒ `false` on load. `copyWith`
adds no wire impact. `kReportSchemaVersion` stays **1**, no migration, under the pre-1.0
carve-out documented at `report_codec.dart:18-22` (additive optional fields loading
backward-compatibly need no bump while no deployed data exists). Existing omission rules
unchanged: `style` omitted when equal to `JetTextStyle.fallback`/`JetBoxStyle.none`, barcode
`color` omitted when black — pre-feature reports round-trip byte-identically (FR-006, FR-014,
SC-004).

## 10. Undo granularity for rapid edits

**Decision**: keep the panel's existing commit discipline — typed fields commit on
blur/Enter, pickers/toggles/swatches commit per pick — each producing exactly one `_commit`
and therefore one undo step (FR-013). No debounce layer is added: the edge case demands "one
undo step per **committed** change, not per keystroke", which commit-on-blur already
guarantees for typing; each stepper click or swatch click is a deliberate committed change,
matching how X/Y/W/H steppers behave today. Selection switches mid-edit discard uncommitted
input because editor state lives in widget state and is rebuilt on selection change — the
panel's existing, tested behavior.
