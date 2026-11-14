# jet_print → jet_charts / jet_office: integration analysis

Date: 2026-11-12. Status: read-only analysis, nothing implemented. Written
from a reading of this repository (jet_print 1.1.0) and of the jet-office
workspace at `c818f64` (jet_charts_core 0.1.0-dev.3, jet_charts_flutter
0.1.0-dev.1, jet_office 0.1.0-dev.1, jet_core 0.1.0-dev.1, all
`publish_to: none`). Sizes are rough (S ≈ days, M ≈ 1–2 weeks, L ≈ 3+ weeks of
focused work) and are estimates, not measurements.

## Summary

1. **The chart move is feasible and the primitive layer fits.** jet_charts_core
   lays a chart out as primitives (rect, path, arc, text, clip) that need only
   a text measurer. jet_print already has a frame-primitive pipeline that
   canvas, preview, PNG and PDF all draw. The shape of the work is a
   *converter into the frame*, not a second painter (see §2 for why this
   differs from the "PDF painter" in the earlier direction).
2. **jet_print's frame lacks four things the chart primitives use:** arcs,
   translucent fills, dashes and clips. All four are small, additive frame
   changes, but each is a change to `FramePrimitive`/`ReportPainter` and so
   touches the golden suites.
3. **XLSX/DOCX export is mostly not ready on the jet_office side.** Charts are
   not in jet_office's public API yet (C1 internal only; C2 XLSX host is a
   draft design, C3 DOCX host is not started). What *is* ready: a typed
   workbook model, `XlsxListExport`, `DocxListExport`, a DOCX document model.
   What is missing for a *report* export is a layout-to-sheet mapping that
   neither library provides.
4. **Nothing can ship to pub.dev until jet_core, jet_charts_core, jet_office
   (and jet_charts_flutter if used) are published.** pub.dev rejects git and
   path dependencies. Order: jet_core → jet_charts_core → jet_office /
   jet_charts_flutter → jet_print.
5. **Recommended order:** publish prerequisites → frame gaps → chart converter
   behind a flag → switch charts → report-to-XLSX (tabular) → report-to-DOCX
   → formula engine later.

## 1. How jet_print draws charts today

| Piece | File | Role |
|---|---|---|
| Model | `lib/src/domain/elements/chart_element.dart` | `ChartElement`: `ChartType {bar, line, pie}`, one `collectionField`, `valueExpression`, `categoryExpression`, `title`, `showAxes`, `showValueLabels`, `showLegend`, single `seriesColor`; `points` filled at fill time (never serialized). `unknownChartType` preserves a newer type name. |
| Codec | `lib/src/domain/serialization/chart_element_codec.dart`, `built_in_element_codecs.dart` | JSON, versioned, forward-compatible. |
| Fill | `lib/src/rendering/fill/element_resolver.dart`, `lib/src/data/collection_rows.dart` | Resolves the collection into `ChartPoint(label, value)`. |
| Geometry | `lib/src/rendering/elements/chart/chart_geometry.dart` (184 lines) | Pure nice-number axis, bar/line/pie geometry. |
| Renderer | `lib/src/rendering/elements/renderers/chart_element_renderer.dart` (325 lines) | `ElementRenderer<ChartElement>.emit` writes **frame primitives** (rect, line, path, text) into a `FrameBuilder`. Fixed gutters (28/14/14/16 pt), hard-coded 7 pt label style, 6-colour `kChartPalette`. |
| Frame | `lib/src/rendering/frame/primitive.dart` | Sealed: `TextRunPrimitive`, `ImagePrimitive`, `LinePrimitive`, `RectPrimitive`, `PathPrimitive` (path = `MoveTo`/`LineTo`/`ClosePath` only). |
| Paint | `lib/src/rendering/paint/report_painter.dart`, `canvas_painter.dart`, `page_rasterizer.dart` | `ReportPainter` interface; `paintFrame` walks the frame. |
| PDF | `lib/src/rendering/export/pdf_painter.dart` (484 lines), `jet_report_exporter.dart` | `ReportPainter` over `package:pdf`'s low-level `PdfGraphics`; fonts embedded from the engine's `FontRegistry` bytes, one rune per glyph. |
| Text | `lib/src/rendering/text/metrics_text_measurer.dart`, `font_registry.dart` | `MetricsTextMeasurer` measures with the same font bytes the PDF embeds. `RenderContext.measurer`. |
| Designer | `designer/.../set_chart_options_command.dart`, `create_element_command.dart`, `element_inspector.dart`, `element_glyph.dart`, 3 ARB files | Authoring of the three types. |

Key property: **a chart is already "emit frame primitives at layout time"**.
Nothing in the PDF or PNG path knows what a chart is. Chart goldens live in
`test/rendering/chart_golden_test.dart`. Today's chart is deliberately small:
one series, three kinds, no secondary axis, no number formats, fixed gutters.

## 2. What a jet_charts_core → PDF path needs

### 2.1 Where the conversion belongs

The earlier direction said "primitives drawn into a PDF painter with its own
text measurer". Reading the code, I recommend a different placement, for the
same reason AGENTS.md states the *One paint path* rule: **convert
`ChartPrimitive`s to `FramePrimitive`s inside `ChartElementRenderer.emit`**, so
the designer canvas, preview, thumbnails, PNG and PDF all keep drawing the
same recorded picture. A PDF-only painter would make the PDF the only place a
chart looks right, which is exactly the "designer lies about what it will
print" failure the rule exists to prevent. The text measurer requirement is
unchanged: the converter runs where `RenderContext.measurer` is available.

### 2.2 Primitive mapping

| jet_charts_core | jet_print frame | Gap |
|---|---|---|
| `RectPrimitive` (fill, stroke, width) | `RectPrimitive` | none (check corner radius: core has none yet either) |
| `PathPrimitive` (points, closed, fill, stroke, width) | `PathPrimitive` (`MoveTo`/`LineTo`/`ClosePath`) | none for polylines |
| `PathPrimitive.dash` | — | **no dash on frame paths or lines** |
| `PathPrimitive.fillOpacity` (J4 areas) | — | **no opacity on shapes** (`ImagePrimitive` has `opacity`; path/rect do not) |
| `ArcPrimitive` (center, radius, innerRadius, start, sweep, fill, stroke) | — | **no arc**; can be flattened to a polyline path in the converter (no frame change), at a cost in file size and edge quality; real arcs/Béziers need `PathCommand` additions (`CubicTo`/`ArcTo`) and painter support in PDF, canvas, rasterizer |
| `TextPrimitive` (text, rect, style, `rotationDegrees`) | `TextRunPrimitive` (lines, style, fontFamily, bounds, `rotation`) | converter must build `TextLine`s (it can call the measurer, which the layout already did), and map `ChartTextStyle` → `JetTextStyle` (family, size, bold, colour). Rotation exists (about the bounds centre, same as core). |
| `ClipPrimitive` (rect, children) | — | **no clip**; core emits it to keep marks inside the plot. Either add `ClipPrimitive`/push-pop to the frame and all painters, or intersect geometry in the converter (rects and polylines can be clipped analytically; arcs and text are not clipped in practice) |
| `ChartColor` (rgb or scheme slot + lumMod/lumOff) | `JetColor` | resolve to rgb in the converter; the theme has an rgb value per slot. Alpha: only via fill opacity |

So four frame gaps: **arc, fill opacity, dash, clip**. The minimum viable
chart (column, bar, line, pie via flattened arcs, no areas, no dash) needs
**none** of them if the converter flattens arcs and drops clips. Areas, donuts
with centre text and dashed lines want opacity and dash. Recommended: add
`fillOpacity` and `dashPattern` to frame `PathPrimitive`/`LinePrimitive` and a
clip pair to the frame; keep arcs flattened first. Each of these changes the
frame equality and therefore every consumer's golden; AGENTS.md's golden rule
applies (deliberate, named in the change).

### 2.3 Text measurer

`jet_charts_core.TextMeasurer` is
`ChartSize measure(String text, ChartTextStyle style)`: single call, no width
limit, no ascent. jet_print's `TextMeasurer` is richer
(`MeasuredText measure(text, JetTextStyle, {maxWidth})`). The adapter is a
dozen lines: wrap `RenderContext.measurer`, map the style, return
`(maxLineWidth, size.height)`. This is the property that makes layout agree
with the PDF: **the same font bytes measure and embed**, which jet_charts_flutter's
`TextPainter`-based measurer cannot guarantee in a PDF. This is the main reason
the PDF/PNG path must use the engine's measurer rather than reuse
jet_charts_flutter.

### 2.4 Fonts

- `ChartTextStyle.fontFamily` is a string; jet_print resolves family names
  through `FontRegistry`. The chart theme's family must be a family the
  registry knows (jet_print's bundled fonts, or a host-registered font), and
  an unknown family falls back the way text elements do. A `ChartTheme` for
  reports needs a font-family default taken from the report/element style, not
  Aptos Narrow/Calibri-style Office defaults.
- Chart label metrics decide axis scale and collision handling; they must be
  measured with the family that is drawn. Because the measurer is the engine's,
  they are.
- Glyph coverage (Turkish, German, `₺`) is already handled by the PDF painter's
  one-rune-per-glyph subsetting (decision 0006); no chart-specific work.

### 2.5 Data binding and the element model

`jet_charts_core.Chart` has many series, per-series kind, secondary axis,
point colours, number format codes, legend, data labels. `ChartElement` has one
series. To use more of core's power the model must grow (series list, optional
`formatCode`, secondary axis, theme), which is a **schema change**: a
forward-compatible `ChartElement` JSON extension, a migration entry in
`domain/serialization/migration.dart`, a CHANGELOG entry, plus designer
inspector and l10n work. A first milestone can avoid this: convert the
existing three-type, one-series `ChartElement` to a core `Chart` at emit time
and change nothing in the model or designer.

### 2.6 Behavioural differences to expect and decide

- Axis ranges: core follows Excel's automatic scaling; jet_print's
  `chart_geometry.dart` uses its own nice-number rules (a `niceAxis` that must
  stay canonical 1/2/5 per project memory). Charts will visibly change on
  upgrade; that is a golden and CHANGELOG event, arguably a user-visible 1.x
  default change under decisions/0004 (defaults count as breaking).
- Gutters/label placement, legend placement, palette: all from `ChartTheme`.
- Pie colours: `kChartPalette` (6) vs core's theme cycle.

## 3. Gaps in jet_charts / jet_office that block this

### Blocking (must be closed before jet_print can depend on them)

1. **Nothing is published; all `publish_to: none`, `0.1.0-dev`.** pub.dev
   refuses a package with path/git dependencies. This is a hard block for
   *any* adoption in a published jet_print.
2. **jet_charts_core is declared "Not done" for several things jet_print charts
   use or will want:** rounded bar corners, gradient fills, a bar chart's
   secondary axis, Excel's other scatter styles. None block parity with
   today's three kinds. Core's own `AGENTS.md` shows J4's secondary axis,
   numeric scatter, negative slice, smooth curve shape and sparkline width are
   still *unconfirmed against Excel*; these are estimates, which matters for the
   XLSX side more than the PDF side.
3. **Core's gate pins Dart `^3.9.0`; jet_print declares `^3.6.0`.** jet_print's
   own SDK constraint must rise to at least `^3.9.0` (Flutter 3.44 ships a new
   enough Dart, so the Flutter floor is not hurt; the Dart claim is). A
   `pubspec.yaml` and CHANGELOG matter, and the CI `floor` job re-resolves at
   3.44.0, so it will tell.
4. **No public API for charts in jet_office.** C1 (DrawingML read/write) is
   internal ("Nothing here is exported from `lib/jet_office.dart` yet"). C2
   (XLSX host: `XlsxSheet.addChart` etc.) is a **draft** spec dated today, not
   approved or built. C3 (DOCX host with an embedded workbook) is not started.
   A DOCX with native charts therefore does not exist; today "a chart is a
   picture in a DOCX" (decision 0010).
5. **Only column, bar, line, area (clustered/stacked/percent) are written to
   DrawingML today.** Pie, donut, scatter, combination and secondary axis are
   C2 work ("the writer refuses them until then"). jet_print has pie today, so
   native pie export waits on C2.

### Not blocking, but worth knowing

- jet_charts_flutter is only relevant if jet_print's designer canvas draws the
  chart through core's widget. It does not need to: the designer already draws
  frame primitives (one paint path). Keep it out of jet_print's dependencies;
  adopting it would also pull its `flutter: >=3.35.0` plus the interaction
  layer for no gain. Dependency list for the chart move is **jet_charts_core +
  jet_core** only.
- Shared dependencies are compatible today: jet_print's lock has `archive`
  4.0.9, `xml` 6.6.1, `intl` 0.20.3, `pdf` 3.12.0; jet_office wants
  `archive ^4.0.9`, `xml >=6.5.0 <8.0.0`. `image` (4.8.0 locked) allows
  archive `^4.0.9` in 4.9.x but 4.12 asks `^4.5.0`, so a later `image` bump
  can pin archive upward; jet_office would then need to follow. Watch that
  pair at publish time.
- Colour handling: core theme colours can be scheme-bound; jet_print has no
  Office theme. A report-driven `ChartTheme.fromColors` (exists in J4) is the
  right entry point; the "Office theme" binding is irrelevant to PDF.
- `jet_office` is larger than jet_print needs for charts only; it is a
  separate decision whether jet_print should depend on jet_office in the main
  package or ship the Office export as an add-on package (the repo already
  has `jet_print_google_fonts` as an add-on precedent), see §5.

## 4. Mapping jet_print's report model to jet_office

### 4.1 The jet_office surface that exists

- **XLSX:** `XlsxWorkbook` (open, edit, save; styles, merges, freeze panes,
  print setup, headers/footers, autofilter, data validation, conditional
  formats, hyperlinks, notes, pictures, tables, structural edits, change
  sets), `XlsxWriter` / `XlsxStreamWriter`, `XlsxSheetWriter`,
  `XlsxListExport` (caption, header row frozen and repeated as print titles,
  autofilter or Excel table, `SUBTOTAL` totals row, number formats via
  `XlsxStyle(numFmt)`, widths in characters).
- **DOCX:** `DocxDocument` (body paragraphs, formatting, styles, numbering,
  tables, sections, headers/footers, fields `PAGE`/`NUMPAGES`, pictures,
  hyperlinks, bookmarks, properties) and `DocxListExport` (A4 portrait, header
  with logo / title / date, footer with page numbers, a `Table Grid` table with
  repeating shaded header row, totals row as caller-supplied values, locale
  number formatting through `jet_core`'s `NumberFormatter`). The DOCX API is
  name-frozen as of D6.
- **Number formats:** `jet_core` implements Excel format codes with a locale;
  jet_print has its own formatting inside the expression engine
  (`expression/` formatting).

### 4.2 jet_print's model, as an export source

A report is a tree: `ReportDefinition` → bands (title, page header/footer,
column header, detail, group header/footer, summary, background, …) →
elements (text with `{...}` expressions, image, shape, barcode, chart,
crosstab/`PivotGrid`) with absolute `JetRect` bounds in points, scopes and
nested `DetailScope`s, groups, variables/aggregates, parameters, watermark,
multi-column bands. It fills into a `RenderedReport`: pages of absolutely
positioned frame primitives. There are two possible export *sources*:

- **Source A, the rendered pages (frame primitives).** Faithful layout, but
  positioned text runs with no table or cell structure. Fine for a picture or
  absolute-position content, wrong for a spreadsheet or a Word table.
- **Source B, the filled structure** (the engine's pass before layout: rows,
  groups, aggregates, band content). This is the only source that can yield
  real cells, real tables, real subtotals. It is what the XLSX/DOCX export
  should read; **jet_print has no public seam that exposes it today.**

### 4.3 What maps, what is partial, what is missing

| jet_print concept | XLSX (`XlsxWorkbook`) | DOCX (`DocxDocument` / `DocxListExport`) | Status |
|---|---|---|---|
| Flat detail list (one band, columns of text/number/date fields) | `XlsxListExport` columns/rows; style from number format | `DocxListExport` table | **Maps directly.** The only need is turning a report's detail band into `XlsxListColumn`/`DocxListColumn` (header text, width, format code, alignment) |
| Column header band | header row | repeated header row | Maps |
| Page header/footer, page numbers, report title | `XlsxHeaderFooter` (`&P of &N`), caption, print titles | header paragraph, footer `PAGE`/`NUMPAGES`, caption | Maps for simple cases; element-level positioning inside a page band does not |
| Title band / summary band | caption / extra rows below | paragraphs before/after the table | Partial: needs a row/paragraph model, not coordinates |
| Groups with header/footer and group totals | none in `XlsxListExport` (one list). Needs sheet-level code: group header rows, subtotal rows, outline/grouping if the model supports row outlines | `DocxListExport` has one table; groups need several tables or merged rows via `DocxTable` calls | **Missing** (assembly code in jet_print or a new jet_office helper) |
| Aggregates (`SUM`, running totals, `{SUM([x])}`) | `XlsxFormula` possible (`SUBTOTAL` is automatic only for the list totals row); report aggregates are computed by the engine | Word has no formulas: pass computed totals | Partial. Values-only is trivial and correct; **live formulas need a formula translator** (expression language → Excel formula), the "shared formula engine" item |
| Number/date formats | `XlsxNumFmt`/format code strings | `jet_core` formatter | Partial: jet_print formats via its own functions; mapping `format(...)` patterns to Excel codes needs a table, and anything else exports as text |
| Static text element | cell | paragraph/cell | Maps |
| Conditional `visible`, `onPrint` hook | evaluated by the engine, absent in output | same | Maps if exporting filled structure; unrepresentable if exporting coordinates |
| Image element | `XlsxSheet` pictures (anchored) | `DocxDocument` inline pictures | Maps; anchoring from bounds only approximate |
| Shape, barcode | rasterize to picture | rasterize to picture | Partial: via `pageToPng`-style rasterization of the element, loses editability |
| Chart element | native chart after jet_office **C2** (needs `addChart`, data bound to cells) | native chart after **C3** (embedded workbook) | **Blocked on C2/C3**; interim: picture |
| Crosstab / `PivotGrid` | a real grid of cells (dynamic columns), possibly an Excel table or a pivot-like layout; nothing in jet_office knows crosstabs | a Word table | **Missing** (dynamic row/column spans, header merges); computing the matrix already exists in `rendering/crosstab/` |
| Multi-column label sheets (band-level `ColumnLayout`) | not representable as a list | table with N columns or a section with columns (`DocxSection` supports columns) | Missing/partial; low priority |
| Watermark | none in XLSX | header picture/text in DOCX (possible, fiddly) | Missing; low priority |
| Page format, orientation, margins | `XlsxPageSetup` | section page setup | Maps |
| Fonts/colours/borders/fills of an element | `XlsxStyle` (font, fill, border, alignment) | run/paragraph/table formatting | Maps cell by cell; borders from `ShapeElement`/styles need rules |
| Absolute positioning (overlapping elements, free layout) | none; spreadsheets are grids | floating shapes/text boxes are opaque in jet_office | **Cannot map**; the exporter must declare which reports it supports (a "tabular-exportable" check, with a diagnostic otherwise) |
| Data source row stream (20k+ rows, `JetPagedDataSource`) | `XlsxStreamWriter` exists for large output | no streaming DOCX | Streaming path needs the engine to hand rows out incrementally |

### 4.4 What is actually missing, as a list

1. A **filled-structure seam** in jet_print (internal first): after fill, before
   paginate, expose bands → rows → cells with resolved text and typed values
   (number/date/string), format code and style per cell, group structure and
   aggregate results. Nothing else is possible without it.
2. A **report-to-grid mapper** (decides which reports are tabular; maps detail
   band elements, ordered by x position, to columns; header/footer/groups to
   rows) and its diagnostics.
3. **Format-code translation** (jet_print format strings → Excel codes).
4. **Group and crosstab assembly** into sheet rows/DOCX tables (neither jet_office
   helper does it).
5. **Charts**: waits for jet_office C2/C3; needs the `ChartElement`→`Chart`
   conversion from §2 plus data written to cells (C2 decision 1: the library
   writes the chart's data table to cells and binds series to them).
6. Optional later: aggregate → Excel formula translation (shared formula
   engine).

### 4.5 A caution on what to promise

`XlsxListExport`/`DocxListExport` are list helpers with deliberate limits
(one list, no groups, no measuring of text, DOCX widths not held to the page).
A WYSIWYG report is a *layout* document; export to a grid format is a
different product ("export the data and structure as a spreadsheet"), not a
rendering of the page. The first release should say exactly that, and cover
the flat-detail-list case.

## 5. Dependency and publishing implications

### 5.1 Hard rule

pub.dev requires every dependency to be a hosted pub.dev package (or SDK).
jet_print depends today on nothing from jet-office. After the change,
jet_print's `pubspec.yaml` would carry `jet_charts_core: ^x` and
`jet_office: ^y` (and transitively `jet_core`). Therefore these must be
**published first**, in order:

1. `jet_core`
2. `jet_charts_core` (depends on `jet_core`)
3. `jet_office` (depends on `jet_core`, `jet_charts_core`)
4. `jet_charts_flutter` only if something published uses it (jet_print should
   not).
5. `jet_print` last.

All three have `publish_to: none` and `0.1.0-dev` versions and path/workspace
dependencies; each needs the usual publish hygiene (versions, CHANGELOG,
README, license, dry-run, example, platform/topics, API docs), which is its own
milestone. Monépro consumes them by git ref today; that must keep working
alongside any publish.

### 5.2 Consequences for jet_print's own releases

- **Until publishing, jet_print can integrate on a branch only** (using
  `dependency_overrides` with a path/git for local development), and **cannot
  release** from that branch. CI for jet_print would need a checkout of
  jet-office or a git override that is removed before `pub publish`.
- **The public API is a promise (1.x semver).** Adding `jet_office` as a
  dependency makes its types potentially part of jet_print's API surface. Keep
  them out of `lib/jet_print.dart` exports (the `encapsulation_test` and
  `exported_member_type_test` guards already enforce no unexported types in
  exported members; extend the same discipline to dependency types). Expose
  the export as jet_print's own types (`JetReportXlsxExporter`,
  `JetReportDocxExporter`) taking/returning bytes.
- **jet_charts_core types must also stay out of the barrel**, with the
  converter private. A `ChartElement` that grows series/themes exposes jet_print
  types, not core's.
- **Package weight and platform reach.** jet_office is pure Dart (web-safe,
  tested in Chrome), so the six-platform claim holds (guarded by
  `platform_claim_test`). It adds `archive` and `xml` to every jet_print app
  even if it never exports Office files. Alternative: a separate add-on
  package `jet_print_office` (precedent: `jet_print_google_fonts`) that depends
  on jet_print and jet_office, so only apps that export Office files pay. The
  chart converter, by contrast, must live in jet_print itself because it is
  part of rendering. Recommendation: charts in-package (core dependency),
  Office export as an add-on package. This also keeps jet_print's version
  independent of jet_office's pre-1.0 churn.
- **SDK floor:** raise jet_print to Dart `^3.9.0` (jet_office/core floor)
  deliberately, with a CHANGELOG line. Flutter floor stays unless Flutter 3.44
  ships Dart below 3.9 (it does not; verify with the `floor` CI job).
- **Pre-1.0 upstream.** jet_office/core are 0.x and "names fixed as of W6/D6"
  only for XLSX/DOCX; chart APIs (core's `Chart`, theme, `layoutChart`) are
  still moving through J5/C2/C3. Depend with caret on a 0.x (meaning minor
  bumps break), pin tightly, and wrap in jet_print's own adapter so the blast
  radius of an upstream rename is one file.
- **Lockfile/CI:** the root lockfile is resolved with Flutter 3.47.7 and
  enforced (`--enforce-lockfile`); adding hosted packages changes it and must
  be resolved under that SDK, not the local one.
- **Golden changes:** charts will look different (Excel-style scale, spacing).
  Goldens are macOS-only and CI's macOS leg is the authority; plan one
  deliberate golden regeneration per chart milestone.

## 6. Proposed milestones

Sizes are the author's estimates. P = prerequisite in jet-office (owner of
that repo), JP = work in this repository.

| # | Milestone | Where | Size | Depends on | Notes |
|---|---|---|---|---|---|
| P1 | Publish-readiness of `jet_core` and `jet_charts_core` (versions, docs, example, dry-run), publish both | jet-office | M | J5 done | Hard prerequisite for any released jet_print chart change. The owner should confirm the API is stable enough to freeze (J4 estimates still open: secondary axis, numeric scatter, smooth curve, sparkline width) |
| P2 | Publish `jet_office` (needs C2 for charts in XLSX, C3 for DOCX) | jet-office | L | P1, C2, (C3) | Decide whether to publish before C2/C3 for the list exports only |
| JP0 | Spike: converter `ChartPrimitive` → `FramePrimitive` for column/bar/line (flattened arcs, no clip/dash/opacity), engine measurer adapter, behind a private flag; `dependency_overrides` locally. Output: side-by-side PNG and a gap list | JP | S | none (local) | Proves §2 without waiting for publishing. Do not merge a path dependency |
| JP1 | Frame gaps: `fillOpacity`, dash, clip (and optionally arcs/curves) in frame primitives, `ReportPainter`, `CanvasPainter`, `PdfPainter`, rasterizer; goldens | JP | M | JP0 | Each is additive to `PathPrimitive`/`LinePrimitive`; keep JSON/schema untouched (frames are not serialized) |
| JP2 | Switch `ChartElementRenderer` to core layout for the existing 3 types and 1 series; theme from report styles; font from registry; update goldens, CHANGELOG, SDK floor raised | JP | M | P1 published, JP1 | First user-visible release. Axis scale and spacing change, state it (decisions/0004) |
| JP3 | Chart model growth: multi-series, number format code, legend/title options, optional secondary axis; schema + migration + designer inspector + 3 ARB files | JP | L | JP2 | Optional; the only milestone that changes report JSON |
| JP4 | Filled-structure seam + report-to-grid mapper + diagnostics for non-tabular reports (internal) | JP | M | none (can start now, independent of jet-office publishing) | Prerequisite of every Office export; deliverable with unit tests on `Source B` |
| JP5 | XLSX export of tabular reports: columns, header, groups (subtotal rows), totals as values, formats, page setup, widths; `jet_print_office` add-on package | JP | L | JP4, P2 | Value-only totals. Charts as pictures until C2 |
| JP6 | DOCX export of tabular reports | JP | M | JP5, P2 | Reuse mapper; no formulas |
| JP7 | Native charts in XLSX/DOCX from `ChartElement` | JP | M | C2 (XLSX), C3 (DOCX), JP3 helps | Uses core `Chart` conversion from JP2 |
| JP8 | Crosstab/`PivotGrid` to XLSX/DOCX | JP | M | JP5 | Dynamic spans |
| JP9 | Shared formula engine: expression language ↔ Excel formulas; live aggregates in XLSX | both | L | JP5 | Explicitly later |

Suggested sequence: **P1 → (JP0 in parallel) → JP1 → JP2** for charts, and
**JP4 in parallel from now** since it needs no publishing, then **P2 → JP5 →
JP6 → JP7 → JP8**, JP3 and JP9 on demand.

## 7. Risks and open questions for the owner

1. **Placement of the chart conversion** (frame vs PDF-only painter): this
   analysis recommends the frame; the earlier direction said PDF painter.
   Please confirm, since it shapes JP0/JP1.
2. **Publishing order and timing** (P1/P2): who publishes and when;
   whether jet_office goes out before C2/C3 for list exports.
3. **Is a visible chart change acceptable in a 1.x minor?** decisions/0004
   counts "the output of a report" as breaking. Either gate the new look
   behind an opt-in on `ChartElement` for a release (default old), or ship in
   2.0.
4. **Add-on package or in-package Office export** (§5.2).
5. **Which reports count as exportable to XLSX/DOCX**: the flat-list case only
   at first?
6. **J4 estimates not yet confirmed against Excel** (secondary axis, numeric
   scatter): C2's owner Excel check (E3) should close them before jet_print
   advertises native charts.
7. **Not verified in this analysis:** the `jet_charts_flutter` implementation
   details beyond its docs, the actual behaviour of `jet_office`'s C2 branch
   (design draft only), the exact `ReportPainter`/golden blast radius of the
   frame changes, and the Dart SDK shipped by Flutter 3.44 (stated from the
   expectation that it is ≥ 3.9; the CI `floor` job is the check).
