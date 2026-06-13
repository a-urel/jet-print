# Contract: Host-Font Registration API (spec 022)

Behavioral contracts C1–C12, each with its test group. TDD red→green (Principle III).
Tests run via `flutter test packages/jet_print` from the repo root. "the registry" =
`FontRegistry` (internal); host-facing surface is the value types + the two `fonts`
threading points.

---

### C1 — `JetFontFace` descriptor
- `JetFontFace(bytes)` defaults `weight: JetFontWeight.normal`, `italic: false`.
- Value equality over `(bytes identity, weight, italic)`.
- **Tests** (`jet_font_test.dart`): defaults; equality/inequality across weight & italic.

### C2 — `JetFontFamily` accepts valid fonts
- `JetFontFamily(name, faces)` with a non-empty name and ≥1 regular face whose bytes parse
  constructs successfully and exposes `name`/`faces`.
- A **regular-only** family is valid (bold/italic optional, FR-001).
- **Tests** (`jet_font_test.dart`): regular-only accepted; full 4-face accepted; faces
  preserved in order.

### C3 — `JetFontFamily` rejects bad input, detectably (FR-010 / SC-006)
- Empty `name` → `ArgumentError`.
- No regular face (e.g. italic-only) → `FontFormatException` whose message names the family.
- A face with empty/malformed bytes → `FontFormatException` naming the family (and the
  offending weight/italic).
- Duplicate `(weight, italic)` within one family → `ArgumentError`.
- All throws are **synchronous** at construction (catchable in a host `try/catch`).
- **Tests** (`jet_font_test.dart`): each rejection; assert exception type + family name in
  message; assert no throw escapes asynchronously.

### C4 — Registry ingest is last-wins & additive (FR-009 / FR-006)
- `FontRegistry()..registerDefault()..registerHostFonts([famA])` resolves `famA`'s bytes/
  metrics for its registered faces.
- Registering two families with the **same name** (or the same family twice) → the **last**
  one's face bytes win; exactly one `families` entry for that name.
- Built-ins remain after host ingest: `hasDefault` stays true; the three built-in names are
  still present; a request for an unregistered family falls back to the default.
- Shadowing a built-in name replaces only that family's registered faces; the default is
  never removed.
- **Tests** (`font_registry_host_test.dart`): last-wins per face; one entry per name;
  `hasDefault` true; built-ins present; default fallback intact when shadowed.

### C5 — Stable, predictable order (FR-008)
- After ingest, `families` = `[JetSans, JetSerif, JetMono, …host families in the order
  supplied]`; identical across repeated reads.
- **Tests** (`font_registry_host_test.dart`): order built-ins-then-host-insertion-order;
  re-read identical; supplying the same host list twice does not reshuffle.

### C6 — Missing variant falls back without error (FR-005)
- A regular-only host family asked for bold/italic returns the regular entry's **same byte
  instance** and metrics; no throw.
- **Tests** (`font_registry_host_test.dart`): `bytesFor(name, weight: bold)` identical to
  regular; `metricsFor` equal.

### C7 — `RenderOptions.fonts` defaults empty; engine carries the registry (WYSIWYG)
- `RenderOptions()` has `fonts == const []`.
- `JetReportEngine().render(t, src, options: RenderOptions(fonts: [famA]))` returns a
  `RenderedReport` whose carried registry resolves `famA`; with `fonts` empty it is
  default-only.
- The carried registry is the **same** one used for layout measurement (not a second
  default-only build).
- **Tests** (`render_options_test.dart`, `rendered_report_fonts_test.dart`): default empty;
  carried registry resolves host family; empty ⇒ default-only; identity/equivalence between
  the measuring registry and the carried registry.

### C8 — Preview, export, print read the carried registry (FR-003 / Principle IV)
- `JetReportPreview` paints frames using `report.fonts` (not a freshly default-only built
  registry).
- `JetReportExporter.toPdf(report)` / `.pageToPng(report, i)` embed/load from
  `report.fonts`.
- `JetReportPrinter.printReport(report)` inherits via the exporter.
- None of these take a new `fonts` parameter.
- **Tests** (`pdf_painter_parity_test.dart`, golden in C9): a report rendered with a host
  family exports/print-PDFs that family (not the default); a default-only report unchanged.

### C9 — Cross-path parity golden (SC-002) ★ headline
- A page whose text uses a host family is **byte-identical** across canvas, preview, PNG,
  and PDF text geometry.
- Existing default-only goldens remain **byte-identical** (SC-005).
- **Tests** (`host_font_parity_golden_test.dart`): one host-family page, four paths equal;
  pre-existing goldens unchanged.

### C10 — Host family in the designer picker (FR-002)
- With `JetReportDesigner(fonts: [famA])`, the family picker lists `famA` (after the
  built-ins), previewed in its **own** typeface, and applying it commits
  `fontFamily: "Acme Brand"` and re-renders the canvas in that font.
- **Tests** (`properties_editor_test.dart`, extends 021 C3): host family listed, ordered
  after built-ins, previewed in own typeface, one undoable commit, canvas updates.

### C11 — Unavailable host family preserved (US2 / SC-003)
- A report whose text names a family **not** in the current registry: opens without error,
  renders in the fallback font, the picker shows the name marked unavailable, and saving
  preserves the name (021 behavior, now exercised for a host name).
- Export of such a report succeeds using the fallback (no block on the missing font).
- **Tests** (`properties_editor_test.dart` + a codec/export case): unavailable marker;
  name preserved on an unrelated edit and on save; export succeeds.

### C12 — PDF text stays real & embedded once (FR-004)
- Text in a host family in the exported PDF is selectable/searchable (real text, not an
  image), and each used host face is embedded once per document.
- **Tests** (`pdf_painter_parity_test.dart`): host face present in the PDF font resources;
  one embedding per used face (byte-keyed cache).

---

## Public API delta (pinned by `public_api_test.dart`)

Added/changed public symbols:
- `JetFontFace`, `JetFontFamily` (rendering/text/jet_font.dart) — **exported**.
- `FontFormatException` — **exported** (previously internal).
- `RenderOptions.fonts` — new field, default `const []`.
- `JetReportDesigner({… List<JetFontFamily> fonts = const []})` and
  `JetReportWorkspace({… List<JetFontFamily> fonts = const []})` — new param.

Unchanged / still internal: `FontRegistry`, the registry carried on `RenderedReport`,
`parseTtfMetrics`, the picker widgets. No new export parameters on `JetReportPreview`,
`JetReportExporter`, or `JetReportPrinter`. No schema/version change.

## Docs & demo (FR-012 / Principle VI)
- Dartdoc on every added symbol: the register-before-build contract, last-wins rule,
  bytes-are-the-input, and the "pass the same list to the designer and `RenderOptions`"
  guidance.
- `CHANGELOG.md` entry.
- Playground: bundle one custom font, build a `List<JetFontFamily>`, pass it to both
  `JetReportWorkspace.fonts` and the `renderReport` `RenderOptions.fonts`; the walkthrough
  in [quickstart.md](../quickstart.md) is reproducible there.
