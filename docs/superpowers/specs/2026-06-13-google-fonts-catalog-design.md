# Design: Bundled Google-Fonts catalog for jet_print (`jet_print_google_fonts`)

**Date:** 2026-06-13
**Status:** Approved (brainstorming) — pending implementation plan
**Builds on:** spec 022 (host-fonts) — the public `JetFontFace` / `JetFontFamily`
seam and the carried-registry render chain this package feeds.

## Problem

Spec 022 opened the seam for a host to contribute fonts *by bytes*, but a host
still has to **source and wire every font itself**. With only the 3 bundled
families available out of the box, the picker feels empty and the feature looks
like it "solves nothing." Reports often need a real choice of typefaces, and a
report's font must be **reliably present, offline, and deterministic** at export
time — not dependent on a runtime network fetch or a fragile dev setup.

## Goal

Ship a **curated, offline, deterministic catalog of open-source (Google Fonts)
families** that drops into the existing 022 seam with near-zero host effort:
`pub add` the package, call one loader, pass the result to the designer and to
`RenderOptions`. No runtime network, no host-side font sourcing.

## Decisions (locked during brainstorming)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | A **separate companion package** `packages/jet_print_google_fonts/`, depending on `jet_print` (public API) + `flutter`. | Keeps the core library lean and headless; consumers opt in. |
| 2 | Bundle **~60 curated OFL/Apache families × 4 faces** (Regular/Bold/Italic/BoldItalic) as **Flutter assets** (not base64-in-Dart). | Fully offline + deterministic; assets load lazily and don't bloat the Dart snapshot. |
| 3 | **Latin + Latin Extended-A subset** of each face. | Keeps the package ~6–10 MB and **covers Turkish** (İ ı ş ğ ç ö ü). Non-Latin scripts are out of scope. |
| 4 | The fetch+subset **dev tool runs at maintainer time, before publish**; outputs are committed. | Consuming projects download nothing and run no tool — bytes ride along with the package. |
| 5 | A fixed **~6–10 MB** is added to every consuming app, even for fonts it doesn't use (Flutter doesn't tree-shake unused assets). | Accepted: negligible for a desktop/web report app; buys simplicity + offline guarantee. |
| 6 | Core `jet_print` is **unchanged**; the package is an ordinary consumer of its public API. | No new core surface; 022 already carries fonts through the render chain. |

## Architecture

A new workspace member, sibling to `jet_print` and the playground:

```
packages/jet_print_google_fonts/
├── pubspec.yaml                 # depends: jet_print, flutter; declares assets:
├── assets/
│   └── fonts/<Family>/<Family>-{Regular,Bold,Italic,BoldItalic}.ttf   # subset, committed
│   └── licenses/<Family>.txt    # OFL/Apache license text per family
├── lib/
│   ├── jet_print_google_fonts.dart        # public barrel
│   └── src/
│       ├── google_font_catalog.dart       # GENERATED: const catalog metadata
│       ├── google_font_entry.dart         # GoogleFontEntry value type
│       └── google_fonts_loader.dart       # loadGoogleFonts(...) + face grouping
└── tool/
    └── fetch_google_fonts.dart            # dev-time: download + subset + generate
```

### Component boundaries

- **`GoogleFontEntry`** — *what:* metadata for one catalog family (`name`,
  `license`, the asset path of each present face). *Depends on:* nothing.
  *Used by:* the loader and any host UI that wants the name list cheaply.
- **`googleFontCatalog`** — *what:* the generated `const List<GoogleFontEntry>`.
  Cheap to read without loading any bytes.
- **`loadGoogleFonts(...)`** — *what:* turns catalog entries into validated
  `JetFontFamily` objects by loading their asset bytes and grouping the 4 faces.
  *Depends on:* `jet_print` public types + an `AssetBundle`. *Used by:* the host
  at startup.
- **`fetch_google_fonts.dart`** — *what:* maintainer-only tool that downloads the
  curated families from Google Fonts, subsets them (Latin + Latin-Ext), writes
  the assets + license files, and regenerates `google_font_catalog.dart` and the
  pubspec asset block. *Not shipped at runtime.*

## Public API

```dart
/// Metadata for one catalog family — cheap to enumerate without loading bytes.
class GoogleFontEntry {
  final String name;                       // display + report-stored name, e.g. "Lora"
  final String license;                    // 'OFL-1.1' | 'Apache-2.0'
  final Map<({JetFontWeight weight, bool italic}), String> faceAssets; // slot -> asset path
}

/// The full curated catalog (generated). Read this for a picker name list
/// without loading any font bytes.
const List<GoogleFontEntry> googleFontCatalog = <GoogleFontEntry>[ /* … */ ];

/// Loads catalog families into the validated `JetFontFamily` list that 022's
/// seam consumes. Reads this package's bundled assets via [bundle]
/// (defaults to rootBundle). [only] limits which families are loaded (reduces
/// startup parse cost + memory; does NOT reduce app bundle size). A family
/// whose bytes fail to load/parse is skipped with a logged warning — never
/// throws mid-load.
Future<List<JetFontFamily>> loadGoogleFonts({
  Iterable<String>? only,
  AssetBundle? bundle,
});
```

## Data flow (host integration — the 022 pattern, one shared list)

```dart
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

final List<JetFontFamily> fonts = await loadGoogleFonts(
  only: <String>['Roboto', 'Lora', 'Inter', 'Merriweather'], // optional
);

JetReportWorkspace(
  controller: controller,
  fonts: fonts,                                   // designer picker + canvas
  renderReport: (ReportTemplate t) => const JetReportEngine()
      .render(t, dataSource, options: RenderOptions(fonts: fonts)), // preview/PDF/PNG
);
```

The designer picker lists the families after the 3 built-ins (022 ordering);
canvas, preview, PDF, and PNG measure/paint/embed from the same bytes. Bytes are
static local assets → exports are reproducible and offline.

## Asset generation tool (dev-time, maintainer-run)

`dart run tool/fetch_google_fonts.dart`:
1. Reads a maintainer-edited **curated list** of ~60 family names + the OFL/Apache
   variants to fetch.
2. Downloads each face from Google Fonts (`fonts.gstatic.com`), verifying a
   checksum.
3. **Subsets** each face to Latin + Latin Extended-A (reusing the approach in
   `jet_print/tool/generate_default_font.dart`).
4. Writes `assets/fonts/...`, `assets/licenses/...`, regenerates
   `src/google_font_catalog.dart`, and updates the pubspec `assets:` block.
5. Output is **committed**; consumers get it via `pub`.

## Licensing

Only **OFL-1.1 / Apache-2.0 / UFL** families (all PDF-embeddable). Each family's
license text is bundled under `assets/licenses/` and recorded on its
`GoogleFontEntry.license`. A test asserts every catalog entry has a bundled
license file.

## Testing

- **Unit (loader):** `loadGoogleFonts()` returns one validated `JetFontFamily`
  per catalog entry; 4-face grouping is correct; `only:` filters; a deliberately
  corrupt asset is skipped (not thrown).
- **Turkish coverage:** a representative sample's parsed metrics resolve glyphs
  for `İ ı ş ğ ç ö ü` (Monepro-critical).
- **Catalog ↔ assets consistency:** every `GoogleFontEntry` face asset exists and
  parses; every entry has a license file.
- **Render/embed parity:** a report using a catalog family exports a PDF that
  embeds that family once and keeps Turkish text selectable; canvas/preview/PDF
  agree (reuses the 022 parity harness).
- **Size budget:** total `assets/fonts/` size is under a committed threshold
  (catches an accidental un-subsetted commit).

## Out of scope (explicit)

- **Operating-system font discovery** — still deferred (the original 022 fork).
- **Non-Latin scripts** (Arabic, Cyrillic, CJK, Greek beyond Latin-Ext) — not in
  the subset; a future multi-script catalog could layer on.
- **Runtime/network fetching** of additional fonts (the rejected Approach A).
- **Pure-Dart server-side rendering without Flutter** — `loadGoogleFonts` uses an
  `AssetBundle`; a host without `rootBundle` must inject a `bundle` or read the
  files itself. Documented, not solved here.
- **Per-app asset tree-shaking** — the full ~6–10 MB ships with the package by
  design decision #5.

## Relationship to spec 022

This package writes **no new core code**. It produces the exact
`List<JetFontFamily>` that 022's `RenderOptions.fonts` /
`JetReportDesigner.fonts` already accept and that the engine carries on
`RenderedReport`. 022 is the foundation; this is the catalog that makes it
useful out of the box.
