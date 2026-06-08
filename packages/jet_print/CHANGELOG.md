# Changelog

All notable changes to the `jet_print` library are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Report model foundation (spec 003 Part 1): pure-Dart geometry value types
  (`JetSize`/`JetOffset`/`JetEdgeInsets`/`JetRect`), `PageFormat`, the element
  model (`ReportElement`, `TextElement`, `UnknownElement`), `ReportBand`/
  `BandType`/`ReportTemplate`, an `ElementCodecRegistry` extension point, and
  versioned JSON serialization with a forward-migration framework
  (`encodeTemplate`/`decodeTemplate`, `schemaVersion`, `SchemaMigration`).
- `JetReportDesigner` — the report designer **shell** widget: a top command bar,
  a left element toolbox (a compact icon toolbar with tooltips), a center design
  surface (a bounded paper page), and a right three-tab context panel
  (Data Source / Outline / Properties) in a theme-driven frame. Layout-only this
  iteration — every control is a non-functional placeholder; the live
  interactions are tab switching, splitter resize of the right panel (down to its
  minimum width), and collapse/expand of the right panel to an icon rail below
  the 1024px width breakpoint. The icon toolbox stays visible at every width.
- `JetPrintLocalizations` — the library's own gen-l10n localization delegate
  covering the designer chrome in English (default/fallback), German, and Turkish,
  exported with its `delegate` and `supportedLocales` so consumers can wire it
  into their app shell. Unsupported locales and missing keys fall back to English.
- Visual model completion (spec 003 Part 2): style value types (`JetColor`
  with hex serialization, `JetTextStyle`, `JetBoxStyle`); text styling on
  `TextElement` (sparse-serialized); new element types `ShapeElement`
  (line/rectangle), `ImageElement` (url/field/base64-bytes sources, `JetBoxFit`),
  and `BarcodeElement` (QR / Code128 / EAN-13 / Data Matrix); and
  `registerBuiltInElementCodecs` to wire all four built-in element codecs.
- Data layer (spec 004): the headless data-access seam — `JetDataSource`
  (factory) → `DataSet` (forward-only cursor) → immutable `DataRow` snapshots,
  with typed `FieldDef`/`JetFieldType` metadata (best-effort column-type
  inference). Three in-memory implementations: `JetInMemoryDataSource`
  (`List<Map>`), `JetJsonDataSource` (JSON array string), and
  `JetObjectDataSource<T>` (typed object list). The architecture test now also
  enforces the `data → domain` boundary.
- Expression engine core (spec 005a): the headless expression language —
  a sealed `JetValue` model (null/bool/number/string/date/error; numbers are
  `double`), a lexer/parser/AST/evaluator pipeline compiling expressions like
  `$F{qty} * $F{price}` and `FORMAT(ROUND($F{total}, 2), '#,##0.00')`, and a
  pluggable `JetFunctionRegistry` (engine extension point) with built-in math,
  string, logic, and format function families. Evaluation never throws — a bad
  operation yields a `JetError` value (rendered `!ERR`); only malformed syntax
  throws `ExpressionException`. `RowEvalContext` resolves `$F{}` from a
  `DataRow` and `$P{}` from a parameter map. The architecture test now enforces
  the `expression -> domain/data` boundary. (Aggregates, variables, groups, and
  `$V{}` references follow in 005b.)
- Aggregates & variables (spec 005b): `ReportVariable` (with `JetCalculation`
  SUM/COUNT/AVG/MIN/MAX/FIRST/LAST or a plain expression, and report/group reset
  scopes), `ReportGroup`, and typed `ReportParameter` declarations join
  `ReportTemplate` and serialize sparsely (still schema v1 — additive). The
  expression engine gains `$V{}` variable references, and a one-pass
  `VariableCalculator` folds per-row values into running/group-scoped
  accumulators with group-break detection (outermost-changed group cascades to
  inner groups). `JetFieldType` moved to the `domain` seam (re-exported from
  `data`) so parameters and fields share one value-type taxonomy. Page/column
  reset scopes are deferred to 008 (pagination).
- Frame, text-metrics & paint backends (spec 006): the rendering display-list
  and first paint backend. `PageFrame` + `FrameBuilder` build a flat list of
  positioned `FramePrimitive`s (text run / image / line / rect / path, each
  tagged with its originating element id). A headless text seam — an in-house
  TTF/OTF **metrics** parser (`parseTtfMetrics`), a byte-keyed `FontRegistry`
  with a bundled Latin default font (Noto Sans, OFL), and a line-level
  `TextMeasurer` (`MetricsTextMeasurer`) that owns word-wrapping — guarantees
  **deterministic line breaks** across backends. A `ReportPainter` abstraction
  (with async `prepare`) and the backend-agnostic `paintFrame` walk drive
  `CanvasPainter` (`dart:ui`). The architecture test now enforces that only
  `CanvasPainter` may import `dart:ui`; `frame/` and `text/` stay headless.
  Cross-backend pixel parity arrives with the PDF/PNG backends in 009. Replaces
  the `ReportDocument`/`ReportLayout` scaffold placeholders.
- **Element renderers (spec 007a).** `ElementRenderer<E>` (measure + emit) paired with
  `ElementCodec<E>` via `ElementTypeRegistry.register`; built-in renderers for text, shape, image,
  and barcode/unknown placeholders; `RenderContext`; `JetConstraints`. `MeasuredText` gains a
  resolved `fontFamily` (006 amendment). Custom element types round-trip through JSON *and* render
  with zero core edits.
- **Fill data pass (spec 007b).** `ReportFiller` turns a `ReportTemplate` + `JetDataSource` into a
  resolved band-instance stream (`FilledReport`) — title/detail/summary/noData — with per-row text
  `expression` and image `FieldImageSource` resolution, report-scoped running/grand totals, frozen
  variable snapshots, and a `ReportDiagnostics` (missing-field warnings; `!ERR` on bad expressions;
  rejection of illegal page-scoped variable use). Adds `TextElement.expression`.
- **Grouping in Fill (spec 007c).** `ReportFiller` now emits `groupHeader`/`groupFooter` band
  instances with group-scoped subtotals at each group break — headers resolve the group's first row,
  footers the last row with the pre-reset subtotal. Adds an optional `ReportBand.group` link and a
  `GroupBandIndex` (fail-fast on duplicate group names; error diagnostics for null/unknown group
  references). Nesting order is derived from the authored group list.

## 0.1.0

Initial scaffold release.

### Added

- Single public entry point `package:jet_print/jet_print.dart`.
- `JetPrintPlaceholder` — a `const`, theme-aware placeholder widget that reflects
  the active `shadcn_ui` theme.
- `jetPrintVersion` — the library's declared version string, establishing the
  SemVer baseline.
- Three internal layer seams (`domain`, `rendering`, `designer`) under `lib/src/`
  with an inward-only dependency rule enforced by an architecture test.
