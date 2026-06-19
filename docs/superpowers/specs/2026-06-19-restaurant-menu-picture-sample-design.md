# Restaurant Menu sample (picture demo) — design

**Date:** 2026-06-19
**Status:** Approved (brainstorming) — ready for implementation plan
**Area:** `apps/jet_print_playground` (consumer playground only; no engine changes)

## Purpose

Add a new playground sample — a **restaurant menu with food pictures** — that is
the first sample to exercise the engine's `ImageElement`. No other sample uses
images today, so this fills a real gap in the demo coverage.

It demonstrates **both** image source kinds the engine supports *without any I/O*:

- **`FieldImageSource`** — per-row, data-bound food photos (the headline feature:
  a collection of items, each with its own picture).
- **`BytesImageSource`** — a fixed, embedded restaurant logo in the page header
  (the "constant image" path).

`UrlImageSource` is intentionally **not** used: the library performs no network
I/O, so a URL source only renders a placeholder. Both paths used here resolve to
real bytes that decode and paint.

## Engine facts this design relies on (already built — do not change)

- `ImageElement{ source: JetImageSource, fit: JetBoxFit }`
  (`packages/jet_print/lib/src/domain/elements/image_element.dart`).
- `JetImageSource` is sealed: `BytesImageSource` (base64-in-JSON, renders
  directly), `FieldImageSource(field)` (resolved at fill), `UrlImageSource`
  (placeholder only).
- Fill resolution: `ElementResolver._resolveImage`
  (`packages/jet_print/lib/src/rendering/fill/element_resolver.dart`) turns a
  `FieldImageSource` into a `BytesImageSource` when the row's field value is
  `Uint8List`, `List<int>`, **or a base64 `String`**. A field that does not
  resolve to bytes produces a warning (not a crash).
- Paint/decode: `canvas_painter.dart` decodes bytes via
  `ui.instantiateImageCodec(bytes)` (Flutter codec → PNG/JPEG/BMP/etc.). The
  in-code generator must therefore emit **real encoded image bytes**.
- There is **no image/bytes field type** in `JetFieldType` (string, integer,
  double, boolean, dateTime, collection, unknown). The photo field is declared
  `string` and carries base64 — consistent with how `BytesImageSource` stores
  base64-in-JSON.

## Data shape (flat — no nested collections)

A flat list of menu items grouped by **category** via a single `GroupLevel`
keyed on `$F{category}` — the same grouping pattern `payroll_sample.dart` uses
for departments. This deliberately avoids the nested-scope / live-aggregation
constraints recorded in the report-engine-aggregation-scope notes; no
`ScopeTotal`, no nested `List<Map>`.

`menuSchema` fields:

| field        | type            | role                                                   |
|--------------|-----------------|--------------------------------------------------------|
| `category`   | `string`        | group key (Appetizers / Mains / Desserts)              |
| `name`       | `string`        | item name                                              |
| `description`| `string`        | item blurb                                             |
| `price`      | `double`        | currency-formatted                                     |
| `photo`      | `string`        | **base64 image bytes** → `BytesImageSource` at fill    |

## Photo source — generated in-code

Per the brainstorming decision (OSS repo; license-clean; keep the synchronous
pure-Dart builder pattern), photos are **synthesized at runtime**, not bundled
as binary assets.

- A pure-Dart helper builds an **uncompressed 24-bit BMP** (file header +
  DIB header + raw BGR pixel rows) as `Uint8List`, base64-encoded into each
  row's `photo` field.
- Each item gets a **distinct hue** (and the header logo a fixed mark) so the
  preview/export visibly shows **distinct per-row pictures** — proving the
  data-binding, even though the swatches are abstract (gradient/solid color),
  not photography.
- BMP is chosen because it is trivial to synthesize byte-by-byte in pure Dart
  (no compression), needs no Flutter binding to *construct*, and is accepted by
  `ui.instantiateImageCodec`. Decoding happens later, at paint time, which
  already runs under a Flutter binding in widget/golden tests.

Consequence: unlike `kSamplePayroll` (a `const` list), `kSampleMenu` cannot be
`const` (bytes are computed) — it is a `final`/function-built list.

## Report layout (bands)

- **Page header band** — restaurant name + tagline, plus an embedded
  `BytesImageSource` logo (small generated mark). Demonstrates the fixed-image
  path.
- **Group header band** (per category) — the category name as a section heading
  (e.g. "APPETIZERS"), keyed on `$F{category}`.
- **Detail band** (per item) — a single per-row band (satisfies the "per-row
  bands must be `detail`" rule):
  - left: `ImageElement` with `FieldImageSource('photo')`, square thumbnail,
    `JetBoxFit.cover`.
  - right: `name` (bold), `description` (muted / smaller), `price`
    (right-aligned, currency-formatted).
- **Page footer band** — a small "prices include tax" note (plain text;
  optional).

## Components / files (mirrors every existing sample)

1. `lib/menu_sample.dart` — `menuSchema` (`JetDataSchema`) and
   `menuSampleDefinition()` (the authored `ReportDefinition`: header w/ logo,
   category group, item detail band, footer).
2. `lib/rendered_menu_example.dart` — `kSampleMenu` rows, `menuDataSource()`
   (`JetInMemoryDataSource(kSampleMenu, fields: menuSchema.fields)`),
   `renderMenuDefinition({JetDataSource? source})`, **plus the in-code BMP
   swatch generator** and the embedded logo bytes.
3. `lib/main.dart` — new tab wired as
   `_DesignerTab(seed: menuSampleDefinition(), dataSchema: menuSchema,
   renderReport: (def) => renderMenuDefinition(...))`.
4. l10n: `tabMenu` label added to `lib/l10n/app_localizations_{en,tr,de}.arb`
   (and regenerated `app_localizations*.dart`).
5. Tests:
   - `test/menu_definition_test.dart` — bands present; group keyed on
     `category`; detail band has an `ImageElement` bound to `photo`;
     `validate()` returns no errors.
   - `test/rendered_menu_example_test.dart` — `renderMenuDefinition()` produces
     a `RenderedReport` whose frame contains one `ImagePrimitive` per item
     (`FieldImageSource` resolved to bytes) and the header logo primitive.

## Testing & non-goals

- **Definition test:** structure + bindings + clean `validate()`.
- **Render test:** per-item `ImagePrimitive`s present; header logo present.
- **No golden changes** anywhere — this is a new, isolated sample + tab.
- **Non-goals:** no engine changes; no bundled binary assets; no async asset
  loading; no `UrlImageSource`; no nested collections or live aggregates.

## Success criteria

1. New "Menu" tab opens a live designer seeded with the authored menu, over
   `menuSchema`, with the same Save/Open/Export seam as other tabs.
2. Preview/PDF/PNG export shows distinct per-row food swatches and the embedded
   header logo — i.e. both `FieldImageSource` and `BytesImageSource` paint.
3. `flutter analyze` clean; both new tests pass; full suite stays green with
   zero golden diffs.
4. Public-API only — the playground consumes the in-repo `jet_print` library
   with no source changes to it.
