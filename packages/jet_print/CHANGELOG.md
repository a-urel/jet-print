# Changelog

All notable changes to the `jet_print` library are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- **Designer edit surface (spec 003-designer-edit-surface) — foundation + MVP +
  undo/redo (in progress).** The center surface is now an interactive WYSIWYG
  canvas. New public surface from the single entry point:
  - `JetReportDesignerController` (`ChangeNotifier`) — holds the in-memory
    `ReportTemplate`, the `Selection`, and unlimited session undo/redo over
    immutable `(template, selection)` snapshots; exposes `open`, `createElement`,
    `moveBy`, live `begin/update/commit/cancelMove`, `select`/`clearSelection`,
    `undo`/`redo`. Headless (no file I/O).
  - `JetReportFormat` — a static facade over the versioned codec
    (`encode`/`decode`/`encodeJson`/`decodeJson`) with built-in element codecs +
    migrations pre-wired; lossless round-trip incl. `UnknownElement` and the full
    parameter/variable/group payload.
  - The `ReportTemplate`-reachable model graph + geometry/style types, plus the
    additive `ReportElement.withBounds` / `copyWith` value-copy helpers.
  - `JetReportDesigner` gains optional `controller` / `initialReport` /
    `onSaveRequested` / `onOpenRequested` (still `const`-constructible — the 002
    contract holds).
  - Canvas: drag-from-toolbox or click-to-place create; click-select with eight
    resize handles; drag-to-move; fit-to-width zoom transform; per-element
    accessibility regions. Element appearance is painted through the **unchanged**
    shared render pipeline (`ElementRenderer.emit` + `CanvasPainter`), cached as a
    `ui.Picture` (Constitution IV — no parallel draw code).
  - Undo/redo wired to the top bar (disabled at the history ends) and to
    canvas-focus-scoped ⌘Z / ⇧⌘Z (Ctrl on non-macOS).
  - Per-handle **resize** with a 4×4 pt minimum floor, plus **snapping** to the
    grid, sibling edges/centers, and band/page bounds with live guide lines;
    Alt/Option bypasses snapping; grid/snap toggles in the top bar.
  - **Multi-select** (shift-click; marquee rubber-band) and **bulk operations** —
    delete, z-order (forward/back/to-front/to-back), cut/copy/paste/duplicate
    (codec-cloned with fresh ids + offset), align (6 ways), distribute, and
    arrow-key nudge (Shift = 10 pt) — each one undoable.
  - Numeric geometry + text editing on the controller (`setGeometry` / `setText`)
    and **inline text editing**: double-click a text element to edit in place
    (Enter commits, Escape cancels), undoable.
  - **Zoom / pan / fit**: top-bar zoom in/out, click the zoom % to fit-to-width,
    ⌘±/⌘0 shortcuts, and trackpad/wheel pan (Ctrl/⌘+scroll zooms), clamped
    25 %–400 %; placement stays pointer-accurate at every zoom (SC-006).
  - **Band-type badges**: each band on the canvas carries a small localized
    caption (Page Header / Detail / Page Footer / …, all eleven `BandType`s) at
    its top-left corner, so authors always know which band they are editing. The
    badge is constant-size UI chrome (legible at any zoom) and never captures
    pointers.
  - The **page viewport scrolls** when the (paper-sized) page doesn't fit:
    horizontal + vertical scrollbars appear and the wheel/trackpad scroll the
    sheet, so the bottom of a full A4 page is always reachable. Drag-to-scroll is
    intentionally disabled so a pointer drag still moves elements / rubber-band
    selects; Ctrl/⌘+wheel still zooms. A page smaller than the viewport is
    centered.
  - The **design surface is a real, paper-sized sheet**: it spans the page
    format's full dimensions (A4 portrait by default), flow bands (title / page
    header / detail / groups / …) stack from the top margin, and the page-/
    column-footer bands are **anchored to the bottom** of the sheet with an empty
    flow gap between — true WYSIWYG, the way a rendered page looks. The surface
    grows if the authored bands exceed the sheet, and a drop in the empty gap
    snaps to the vertically nearest band.
  - The **paper page surface is a constant white in every theme** (WYSIWYG —
    it represents printed paper, and report content is emitted with print colors
    such as dark text that only read on white). Only the surrounding canvas and
    the app chrome follow the light/dark theme; the design-time chrome drawn on
    the page (band separators, band badges, the empty hint) uses a fixed
    paper-relative palette so it stays legible on white in dark mode too.
  - **Resize handles show directional cursors on hover**: each of the eight
    handles exposes the matching resize cursor (diagonal `↖↘`/`↗↙` for corners,
    `↕`/`↔` for edges) so the pointer signals which edges a drag moves. Corners
    sit above edges in the overlay so an overlapping edge hit-area can't mask the
    diagonal cursor when zoomed out. On macOS — whose public cursor set has no
    diagonal — the corners drive the native window-resize `NSCursor` directly, so
    they look the same as everywhere else.
  - **The report (page) and individual bands are now selectable**, not just
    elements. Clicking a band's empty area selects that band; clicking the paper
    off any band selects the report; clicking off the paper clears. The selection
    targets are mutually exclusive. `Selection` gains `Selection.band(i)` /
    `Selection.report()` with `bandIndex` / `isReport`; the controller gains
    `selectBand` / `selectReport`.
  - **Bands resize vertically.** A selected band shows a single divider handle on
    its growth-facing edge (the bottom for a flow band, the top for a
    bottom-anchored footer) — no element-style corner/side handles, since a band
    only has a height. Dragging it changes the band height (floor-clamped, one
    undoable step); `setBandHeight` exposes the same change numerically. A
    selected report shows an outline only (the sheet is a fixed format).
  - **The Outline panel is now model-driven** (was static sample content): it
    renders the live template as a tree (Report root → bands → elements), tapping
    a row selects that object through the controller (report / band / element),
    and the row matching the current selection is highlighted (and marked
    selected for accessibility). The disclosure chevron collapses/expands a
    branch independently of selection.
  - **The Properties panel is now a model-driven, context-aware inspector** (was
    static sample content): a selected element exposes live **X / Y / W / H**
    fields (committed through `setGeometry`) and, for a text element, its **text**
    (`setText`) — each edit one undoable step, with steppers for ±1 nudges and
    commit on Enter or blur; a selected band exposes its **height**
    (`setBandHeight`); the report shows read-only page info; and nothing/a
    multi-selection shows a friendly empty state. Fields reflect the live model,
    so a canvas move/resize updates the numbers and vice-versa.
  - **Selecting an element scrolls it into view.** When a selection comes from the
    Outline panel (or any non-canvas source), the canvas scrolls the element into
    the viewport so the user sees what they selected — a no-op when it is already
    visible. This completes the canvas ↔ Outline ↔ Properties two-way sync.
  - **An "Arrange" menu in the top bar** gathers the selection-wide layout
    actions: align (left / center / right / top / middle / bottom), distribute
    (horizontally / vertically), and z-order (bring to front / forward, send
    backward / to back) — each one undoable. The trigger enables once an element
    is selected; the align/distribute items further require two or more (a lone
    element has nothing to align against), while the z-order items act on a single
    element too.
  - *Remaining for later increments:* polish (a11y semantics, design-surface
    goldens, the 200-element perf smoke, and the tester app's file open/save
    wiring).
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
- **Layout engine (spec 008a).** `ReportLayouter` lays a `FilledReport` band stream onto pages:
  it measures body bands (grow-only, via the element renderers), stacks and paginates them in the
  per-page body region, and repeats `pageHeader`/`pageFooter` chrome on every page, emitting one
  `PageFrame` per page plus diagnostics. A pure `BandMeasurer` computes grown band heights. Chrome is
  emitted as authored (no expression evaluation yet — page-scoped substitution arrives in 008c);
  unresolved chrome bindings, chrome that overcommits the page, and not-yet-supported
  column/background bands are reported as diagnostics.
- **Group-aware pagination (spec 008b).** Two opt-in `ReportGroup` flags: `reprintHeaderOnEachPage`
  repeats a group's header band(s) at the top of each continuation page it spans, and `keepTogether`
  moves a whole group instance to a fresh page rather than splitting it (when it fits a fresh page,
  accounting for any repeated outer headers). Group identity is carried into the internal Fill→Layout
  IR via `FilledBand.group`; the schema is unchanged (the codec contract comment now codifies the
  pre-1.0 additive-optional-fields carve-out). A flag on a header-less group is a no-op + info.
- **Page-scoped substitution (spec 008c).** `pageHeader`/`pageFooter` text expressions are evaluated
  at layout time and substituted at their authored bounds: `$V{PAGE_NUMBER}`/`$V{PAGE_COUNT}` (as
  integer strings, e.g. `Page 1 of 3`) and report `$P{params}` (threaded through the IR as the
  normalized `FilledReport.params`). A new read-only `Expression.references` gives complete,
  branch-independent reference analysis, so unavailable chrome references (`$F{}`, non-page `$V{}`)
  are diagnosed once per element regardless of short-circuiting. Substitution is fixed-bounds (no
  repagination, no chrome box growth); parse/evaluation failures render `!ERR`. The schema is
  unchanged (`FilledReport.params` is internal IR).

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
