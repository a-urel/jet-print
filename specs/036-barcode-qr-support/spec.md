# Industry-Grade Barcode / QR Code Support

**Feature branch:** `036-barcode-qr-support`
**Status:** Draft (design approved via brainstorming 2026-06-18)
**Supersedes:** the spec-007a barcode *placeholder* (`BarcodeElementRenderer` drew a labeled outline; real symbology was explicitly deferred to "a dedicated later spec" — this is it).

## Summary

Replace the placeholder barcode renderer with **real, scannable symbology rendering** for a retail/logistics symbology set, add **field-or-literal data binding**, **auto-detect symbology** (with explicit override), and the industry-grade rendering details that make a symbol actually scan: **human-readable text (HRI)**, **quiet zones**, **QR error-correction level**, and **crisp bar/module fidelity**. Invalid data **auto-fixes where the spec allows, else renders the existing placeholder + a diagnostic**.

Encoding is provided by the pure-Dart [`barcode`](https://pub.dev/packages/barcode) package (Apache-2.0, by the same author as the already-depended-on `pdf` package — and already present transitively via `pdf`), wrapped behind an **internal `BarcodeEncoder` seam** so the rest of the system depends only on first-party geometry types — never the third-party package.

This is a **WYSIWYG** feature: bars/modules are emitted as the existing pure-Dart display-list primitives (`RectPrimitive`, `TextRunPrimitive`), which both the on-screen canvas painter and the PDF exporter already consume, so canvas / preview / export render identically.

## Goals

- Render genuinely scannable symbols for: **QR Code, Data Matrix, PDF417, Aztec** (2D) and **Code 128, Code 39, EAN-13, EAN-8, UPC-A, ITF-14** (1D).
- Let authors bind the encoded value to a **single data-source field** *or* type a **literal** — mirroring the literal-plus-optional-dynamic idiom already used by text (`text` + `expression`) and image (literal + `FieldImageSource`).
- Default to **`Auto`** symbology: infer the concrete symbology from the resolved value by a documented priority; always allow the author to pin a concrete symbology.
- Emit industry-grade detail: **HRI text** under 1D symbols, mandatory **quiet zones**, editable **QR ECC level**, and **crisp** bar/module edges with square 2D modules.
- Surface **diagnostics** (invalid value for the chosen symbology; unresolved bound field) at fill time and in the designer, never as a crash or a blank.

## Non-Goals / Out of Scope

- Symbologies beyond the set above (e.g. MaxiCode, GS1 composite, MicroQR, PDF417 macro). The encoder seam keeps the door open; this slice does not expose them.
- Full free-form **expression** binding for the value (e.g. `CONCAT([a], [b])`, functions). Binding is **field-or-literal** only. (A future slice could widen to expressions; the resolver path is intentionally modeled on the existing expression flow so this is additive later.)
- Barcode **scanning/decoding** (read side). This is encode/render only.
- Rotating barcodes (vertical/angled). Symbols render in the element's natural orientation within `bounds`.
- A pluggable/registered encoder *registry* (the codebase has registries for renderers/codecs). One built-in adapter, internal; registry is YAGNI for now.

## User Scenarios

1. **Retail label.** An author drops a barcode, binds it to the `sku` field, leaves symbology on `Auto`. A 13-digit SKU renders as EAN-13 with the digits printed beneath and a quiet-zone margin; the printed PDF scans.
2. **Shipping carton.** Author pins `ITF-14`, binds to `gtin`. A 13-digit value auto-completes its check digit; a non-numeric value renders the placeholder and shows "not valid for ITF-14".
3. **QR to a tracking URL.** Author types a literal `https://track.example/{...}` (or binds a `trackingUrl` field), symbology stays `Auto` → inferred QR; author bumps ECC to `H` for a damaged-label environment.
4. **Wrong data.** A bound field resolves to letters where EAN-13 needs digits. The symbol can't auto-fix, so the placeholder renders and the preview/host receives a clear diagnostic; nothing crashes.

## Design Overview (approved)

### Domain model — `BarcodeElement` (`domain/elements/barcode_element.dart`)

| Field | Type | Default | Notes |
|---|---|---|---|
| `symbology` | `BarcodeSymbology` | `auto` | enum expands (see below) |
| `data` | `String` | — | the literal value |
| `dataField` | `String?` | `null` | when non-null, the encoded value comes from this field; else `data` is used |
| `color` | `JetColor` | `black` | bar/module color |
| `showText` | `bool` | `true` | HRI text under 1D symbols; ignored by 2D |
| `quietZone` | `bool` | `true` | reserve the mandatory light margin |
| `eccLevel` | `QrErrorCorrectionLevel` | `m` | QR only (L/M/Q/H); ignored otherwise |

`BarcodeSymbology` = `auto, qrCode, code128, ean13, ean8, upcA, code39, itf14, dataMatrix, pdf417, aztec`.

`copyWith`, `==`, `hashCode`, `toString` updated for the new fields. `withBounds` unchanged in shape.

**Binding shape decision:** nullable `dataField` *alongside* the existing `data` (not a new sealed `BarcodeSource` class) — smallest, fully backward-compatible change; resolve path mirrors `ImageElement` field resolution; `dataField` (when set) wins over `data`, exactly as text's `expression` wins over `text`.

### Encoder seam (new, pure Dart, no Flutter, no diagnostics)

```
src/rendering/elements/barcode/
  barcode_encoder.dart          // BarcodeEncoder interface + BarcodeEncodeResult
  barcode_symbol.dart           // first-party geometry: bars / module matrix + HRI text runs
  symbology_inference.dart      // inferSymbology(value) -> concrete BarcodeSymbology
  package_barcode_encoder.dart  // THE ONLY file importing the `barcode` package
```

- `BarcodeEncoder.encode(symbology, value, {showText, eccLevel}) -> BarcodeEncodeResult`, where the result is either a `BarcodeSymbol` (a normalized geometry — a list of bar rects *or* a `bool` module matrix, plus optional HRI text runs, in a unit/module space) or `BarcodeInvalid(reason)`.
- **Auto-fix then validate** lives here: compute/repair check digits and pad where the spec allows; if still invalid → `BarcodeInvalid`. The `barcode` package validates and throws on bad input; the adapter catches and maps to `BarcodeInvalid` so the third-party exception type never escapes the seam.
- `inferSymbology(value)` resolves `auto` to a concrete symbology by a **documented priority** (see FR-004). `auto` never reaches the encoder unresolved.
- Only `package_barcode_encoder.dart` imports the third-party package; all other code depends on first-party `BarcodeSymbol`.

### Renderer (`rendering/elements/renderers/barcode_element_renderer.dart`)

- Resolve symbology (`auto` → `inferSymbology`; a design-time bound/unresolved field — no value to infer from — falls back to a fixed **QR** preview symbology), call the encoder.
- **Valid** → translate the symbol to primitives: each bar/module → a filled `RectPrimitive(fill: el.color)`; HRI → a measured `TextRunPrimitive`. Apply the **quiet-zone** inset inside `bounds`, **snap** bar/module edges to crisp widths, keep 2D modules **square**.
- **Invalid** → fall back to the existing `emitPlaceholder` (render-don't-crash).
- `measure` stays fixed-size (returns `bounds` size).
- The renderer emits **no diagnostics** (`RenderContext` carries only a `TextMeasurer`). Diagnostics are emitted one layer up (fill + designer).

### Fill-time resolution (`rendering/fill/element_resolver.dart`)

A new barcode branch, modeled on the image-field path:

1. `dataField != null` → read the field from the row, stringify, return a resolved `BarcodeElement` with `data = <value>`, `dataField = null` (a flattened snapshot, like text `expression` → resolved `text`).
2. Schema-aware unresolved check (reusing `knownFields`): an undeclared `dataField` emits the existing "field not in the data source" warning (deduped via `warnedFields`) and resolves to empty → placeholder.
3. The element still renders a placeholder for invalid data (render-don't-crash). **The invalid-value diagnostic is raised in the designer, not the fill layer** — `rendering/fill/` is forbidden by the layer-boundary invariant from importing the encoder (`rendering/elements/`), so the validity check (which needs the encoder) lives where the import is legal: the designer Properties panel surfaces an inline "not valid for this symbology" hint for a literal value. A purely headless fill/export renders the placeholder without a separate validity diagnostic. (Resolution decision, 2026-06-18.)

Resolution turns *domain → domain* (flatten binding, emit diagnostics); the renderer turns *domain → primitives*. Each encodes once; the resolved model stays serializable and Flutter-free.

### Serialization (`domain/serialization/barcode_element_codec.dart`)

Purely **additive**, backward-compatible:

- Write `dataField`, `showText`, `quietZone`, `eccLevel` **only when non-default** (matching the existing `if (color != black)` idiom) so existing documents round-trip byte-identically and goldens stay stable.
- Read with default fallbacks when absent. Old files (the four original symbologies, no new fields) load unchanged.
- New symbology / ECC enum values serialize by `.name`. **No new migration** — additive optional fields and enum values don't break the v2 schema.

### Designer authoring (`designer/layout/panels/properties_panel.dart`, `controller/commands/`, l10n)

- **Symbology picker** — dropdown: `Auto` + every concrete type (default `Auto`).
- **Data editor (field-or-literal)** — a toggle: *Field* shows a data-source field dropdown (reusing the panel's existing field-choice helper); *Literal* shows a text field. Sets `dataField` or `data`.
- **Options, symbology-gated** — `showText` + `quietZone` switches for 1D types; `eccLevel` dropdown only for `qrCode`; color stays.
- **Inline validation hint** — reuse the `_UnresolvedHint`/diagnostic pattern: a localized warning when the bound field is unresolved or a literal value is invalid for a pinned symbology. For `auto` + literal, show the *inferred* type as a hint.
- **Commands** (one per edit, matching `setBarcodeColor`): `setBarcodeSymbology`, `setBarcodeData`, `setBarcodeDataField`, `setBarcodeShowText`, `setBarcodeQuietZone`, `setBarcodeEccLevel` — each an undoable `copyWith` commit.
- **Toolbox / create** — entry unchanged; `CreateElementCommand` default becomes `symbology: auto` with a sample literal so a freshly-dropped barcode renders something real.
- **l10n** — new ARB keys across **en/de/tr**, regenerated via gen-l10n.

## Functional Requirements

- **FR-001** The system MUST render scannable symbols for QR Code, Data Matrix, PDF417, Aztec, Code 128, Code 39, EAN-13, EAN-8, UPC-A, and ITF-14.
- **FR-002** `BarcodeElement` MUST carry `symbology` (incl. `auto`), `data`, `dataField`, `color`, `showText`, `quietZone`, and `eccLevel`, with the defaults in the table above.
- **FR-003** When `dataField` is non-null, the encoded value MUST come from that data-source field at fill time; otherwise the literal `data` is used.
- **FR-004** `Auto` symbology MUST be inferred from the resolved value by this documented priority: URL/multiline/non-ASCII/over-length → QR; all-digits of length 13 → EAN-13, 12 → UPC-A, 8 → EAN-8, 14 → ITF-14; any other all-digits → Code 128; any remaining (alphanumeric) → Code 128. Ties are broken in this order. An explicit (non-`auto`) symbology MUST override inference. When there is no value to infer from (a bound field at design time), the canvas MUST preview as QR.
- **FR-005** Invalid data MUST be auto-fixed where the symbology spec allows (e.g. compute a missing EAN-13 check digit, pad ITF to even length); when it cannot be made valid the element MUST render the existing placeholder, and the designer MUST surface a validity diagnostic for an invalid literal (see FR-016 for why this is author-time rather than fill-time).
- **FR-006** 1D symbols MUST render HRI text beneath the bars when `showText` is true; 2D symbols MUST ignore `showText`.
- **FR-007** Symbols MUST reserve a quiet zone within `bounds` when `quietZone` is true, never overlapping bars/modules.
- **FR-008** QR symbols MUST honor `eccLevel` (L/M/Q/H, default M); non-QR symbologies MUST ignore it.
- **FR-009** Bars/modules MUST render with crisp (snapped) edges and 2D modules MUST be square, preserving scannability at the element's authored size.
- **FR-010** Bars/modules MUST render in the element's `color`; HRI text inherits a legible default tied to that color.
- **FR-011** Encoding MUST be provided behind a first-party `BarcodeEncoder` seam; only one adapter file may import the third-party `barcode` package, and the third-party exception/types MUST NOT escape the seam.
- **FR-012** A bound field absent from the active data-source schema MUST emit the existing unresolved-field diagnostic (deduped) and render the placeholder.
- **FR-013** The codec change MUST be additive and backward-compatible: existing documents load and round-trip byte-identically; new fields are written only when non-default; no new migration is introduced.
- **FR-014** The designer MUST let an author choose symbology (incl. `Auto`), switch the value between a bound field and a literal, toggle `showText`/`quietZone`, set QR `eccLevel` (QR only), and set `color`, each as an undoable command.
- **FR-015** The designer MUST show an inline validation hint when a bound field is unresolved or a literal value is invalid for a pinned symbology, localized in en/de/tr.
- **FR-016** Diagnostics MUST NOT originate in the renderer (which only renders bars or a placeholder). The **binding** diagnostic (a `dataField` not in the data-source schema) originates in the **fill layer** (it needs only `knownFields`, no encoder). The **validity** diagnostic (a value invalid for its symbology) originates in the **designer**, because the encoder lives under `rendering/elements/` and the layer-boundary invariant forbids `rendering/fill/` from importing it. (Resolution decision, 2026-06-18 — the plan originally placed validity in fill; that violated the layer test.)

## Key Entities

- **`BarcodeElement`** — the report element (domain, Flutter-free, serializable).
- **`BarcodeSymbology`** — the symbology enum incl. `auto`.
- **`QrErrorCorrectionLevel`** — `l, m, q, h`.
- **`BarcodeEncoder` / `BarcodeEncodeResult` / `BarcodeSymbol` / `BarcodeInvalid`** — the first-party encoder seam and its pure geometry result.
- **`PackageBarcodeEncoder`** — the sole adapter onto the third-party `barcode` package.
- **`inferSymbology`** — pure value → concrete symbology function.

## Success Criteria

- **SC-001** Each of the ten symbologies renders a symbol that decodes to its input value with a standard scanner / decoder for representative valid inputs.
- **SC-002** A barcode bound to a data-source field encodes the per-row resolved value; the same element with a literal encodes the literal.
- **SC-003** `Auto` selects the expected concrete symbology for the FR-004 priority table (covered by a unit table: URL→QR, 13-digit→EAN-13, 12→UPC-A, 8→EAN-8, 14→ITF-14, alphanumeric→Code 128).
- **SC-004** EAN-13 supplied 12 digits auto-completes the check digit and renders; supplied letters renders the placeholder and emits a diagnostic.
- **SC-005** 1D symbols with `showText` print the human-readable value; with quiet zone enabled the light margin is present; QR honors the selected ECC level.
- **SC-006** Canvas and PDF export render the same symbol (shared primitives) — a representative multi-symbology golden matches on both paths.
- **SC-007** Existing report documents load unchanged and round-trip byte-identically; pre-existing goldens are unchanged by this feature (only new barcode goldens are added).
- **SC-008** `flutter analyze` is clean, `dart format` is a no-op, and the full `flutter test` suite (package + playground) is green.
- **SC-009** Only one file imports the `barcode` package (enforceable by grep / an architecture test).

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — encoder seam internal under `src/`; public surface grows only by additive enum values + `BarcodeElement` fields (SemVer-minor). |
| II. Layered architecture | PASS — domain stays Flutter-free; encoder seam (pure Dart) isolates the dependency; renderer = domain→primitives; resolver = domain→domain + diagnostics. Dependencies point inward. |
| III. Test-First (NON-NEGOTIABLE) | PASS — every task Red→Green; domain/codec/encoder/renderer/fill/designer/goldens covered. |
| IV. Rendering fidelity / WYSIWYG | PASS — bars/modules are existing primitives consumed identically by canvas and export; golden parity asserted (SC-006). |
| V. Versioned serialization | PASS — additive optional fields, written only when non-default; no migration; back-compat asserted (SC-007). |
| VI. Docs / DX | PASS — dartdoc on new types; `flutter analyze` + `dart format` gates (SC-008); designer gains real authoring affordances. |

## Risks & Mitigations

- **Third-party API drift** — the `barcode` package's geometry API (e.g. `make()` element stream vs. matrix) is confirmed during planning; the seam means any adaptation is confined to one file.
- **Auto-detect ambiguity** — inherent (a 13-digit value is valid as several symbologies). Mitigated by a documented priority (FR-004) **and** an always-available explicit override; the designer shows the inferred type for literals.
- **Dynamic data vs. WYSIWYG** — a bound field's true symbology/symbol is only known at fill time; the canvas shows a default preview. Documented behavior, mirrors text expression bindings.
- **Golden churn** — non-default-only serialization + additive codec keep existing goldens stable; only new barcode goldens are introduced (SC-007).

## Dependencies

- Promote `barcode` (pure Dart, Apache-2.0) from a transitive dependency (it already arrives via `pdf`) to a **direct** dependency in `packages/jet_print/pubspec.yaml`, since the adapter imports it directly (`depend_on_referenced_packages`). Same author as the existing `pdf` dependency; permissively licensed (Constitution-compatible). Pin the resolved version (2.2.9 at time of writing).
