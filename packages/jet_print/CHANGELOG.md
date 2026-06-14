# Changelog

All notable changes to the `jet_print` library are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- **Per-group page breaks (`ReportGroup.startNewPage`).** A group can begin each
  instance after its first on a fresh page; the first instance never forces a
  leading blank page. Combined with grouping per record (e.g. one group per
  invoice) this yields one record per page. Additive and optional — serialized
  only when `true`, so `kReportSchemaVersion` is unchanged and existing reports
  round-trip byte-identically. Editable in the designer: selecting a group
  header/footer band reveals a **Group → Start on new page** toggle in the
  Properties panel (`controller.setGroupStartNewPage`), as one undoable step.
- **Host & system fonts in font pickers (spec 022-host-fonts).** A host can now
  contribute its own fonts, selectable in every designer picker and rendered
  byte-identically across canvas, preview, PDF, and PNG:
  - **Two bytes-in value types:** `JetFontFace` (`{bytes, weight, italic}`,
    value-equal by bytes identity) and `JetFontFamily` (`{name, faces}`). A
    family **validates its faces eagerly and synchronously** at construction —
    it requires at least a regular face, parses every face, and rejects an
    empty/malformed/regular-less/duplicate-slot family — so a bad font is caught
    where it is assembled, never later inside a widget `build()` or a `render()`.
  - **`FontFormatException` is now exported** — the single detectable rejection
    type.
  - **Two host touch-points, one shared list:** `RenderOptions.fonts` (threaded
    through the render chain) and `fonts` on `JetReportDesigner` /
    `JetReportWorkspace` (the designer picker + canvas). Pass the **same**
    `List<JetFontFamily>` to both. Duplicate family names resolve
    last-registration-wins; missing bold/italic fall back to regular; built-ins
    are listed first, then host families in the order supplied.
  - **WYSIWYG by construction:** `JetReportEngine.render` builds **one**
    `FontRegistry` (defaults + host families), measures with it, and carries it
    on the returned `RenderedReport`; the preview, the PDF/PNG exporter, and the
    printer read it off the report instead of building a parallel default-only
    registry — they gain **no** new parameter. `FontRegistry` stays internal.
  - **No schema change:** reports still store only the font-family *name*
    (`schemaVersion` unchanged). A report naming a font absent in the session
    opens without error, renders in a fallback, shows the name marked
    unavailable in the picker, preserves it on save, and still exports.
- **Format properties — font & color editors (spec 021-format-properties).** The
  Properties panel now edits the style the model already carries, per element
  type:
  - **Text — a new Font section:** family picker (enumerates the designer's
    registered families, each previewed in its own typeface; an unregistered
    stored family is shown as *unavailable* and preserved verbatim until
    repicked), size field clamped to 4–144 pt, **B/I/U** toggles (Bold is active
    iff the weight is exactly `bold`; `medium`/`semiBold` are preserved until the
    toggle is operated), a swatch + hex color editor, and left/center/right
    alignment segments (a stored `justify` shows no active segment and survives
    unrelated edits).
  - **Underline, end-to-end (the one net-new attribute):** `JetTextStyle` gains
    `underline` (default `false`, serialized only when `true`). Both painters
    draw it as an explicit stroked segment from one shared geometry helper —
    never `TextDecoration` — so canvas, PNG preview, and PDF export are identical
    by construction.
  - **Shape — a new Appearance section:** fill color with **None** (hidden for
    line shapes), outline color with **None**, and outline width clamped to
    0–20 pt. Width 0 hides the outline at a single renderer seam while the
    stored color is remembered, so stepping back above 0 restores it.
  - **Barcode — a color row** bound to `BarcodeElement.color`; the placeholder
    rendering is tinted with it (real symbology rendering will inherit it).
  - **Color editing rules:** display is `#RRGGBB` (or `#AARRGGBB` when
    translucent); a palette pick or 6-digit hex preserves the stored alpha, an
    8-digit hex sets it, malformed input is rejected with the last valid value
    restored and no history entry.
  - New public surface is additive and minimal:
    `JetTextStyle.underline` + `JetTextStyle.copyWith` (sentinel `fontFamily`),
    `JetBoxStyle.copyWith` (sentinel `fill`/`stroke` — explicit null = the None
    states), `BarcodeElement.copyWith`, and three controller mutators —
    `setTextStyle`, `setShapeStyle`, `setBarcodeColor` — each one undoable,
    notifying step that no-ops (no history, no notification) on an equal value,
    a missing id, or a wrong element type. The editors, commands, underline
    helper, and `FontRegistry` (including its new internal `families` getter)
    stay private.
  - **One bundled font, all four faces.** The library now ships a single
    built-in family — **`Default`** (a Latin subset of Noto Sans, OFL 1.1) — in
    Regular, **Bold, Italic, and Bold Italic** subsets covering one codepoint
    set, so B/I/U edits are visible on canvas, preview, and export alike.
    Intermediate weights (`medium`/`semiBold`) resolve to Regular via the
    fallback chain. `Default` is the always-resolvable render fallback (FR-006):
    text with no/unknown family always renders. The designer preloads its
    Regular face into the engine at mount so picker options preview in their own
    typeface before the canvas has painted them. Every other family is
    contributed by the host (see above) — the library bundles no serif or
    monospaced font of its own. (~112 KB embedded font data; the PDF exporter
    embeds each face once per document, only when used.)
  - **Canvas right-click menu now dismisses on a primary click anywhere on the
    canvas.** It previously closed only when clicking the surrounding chrome,
    because the canvas gesture layer consumed the tap before the menu's own
    dismiss handler saw it. The dismissing click still acts on the canvas —
    selecting or deselecting as usual — and changes no document state.
  - **Serialization:** `kReportSchemaVersion` stays **1**, no migration.
    `underline` is additive-optional; all existing omission rules are unchanged,
    and pre-feature reports load and re-save **byte-identically** (pinned by a
    frozen fixture test). ~35 new localized strings ship in en/de/tr.

- **Visual shape gallery in the Properties pane (spec 020-shape-gallery).** When a
  single shape element is selected, the Properties panel now shows a **Shape**
  section with eight thumbnails — line, rectangle, **ellipse, triangle, diamond,
  pentagon, hexagon, star** — drawn through the same geometry the renderer uses,
  so the picker icon is exactly what the canvas, preview, and export produce. The
  active form is highlighted; a single click switches the shape's form in one
  undoable step, preserving its bounds and fill/stroke. Re-picking the active form
  is a no-op (no history, no notification).
  - New public surface is additive and minimal: six new `ShapeKind` values
    (`ellipse`, `triangle`, `diamond`, `pentagon`, `hexagon`, `star`),
    `JetReportDesignerController.setShapeKind(String, ShapeKind)` (one undoable,
    notifying step), and `ShapeElement.copyWith(...)` plus an optional
    `unknownForm` field on the already-public immutable type. The geometry
    (`shapePath`), the `SetShapeKindCommand`, and the gallery widget stay private.
  - **Rendering fidelity (WYSIWYG):** every closed form emits a single
    `PathPrimitive` from one shared `shapePath`, so canvas, preview, and PDF/PNG
    export agree with no forked render path and no new painter code. The ellipse
    is a smooth 64-segment inscribed polygon (no curve primitive needed).
  - **Lossless forward-compatible serialization:** `kReportSchemaVersion` stays
    **1** with no migration. Known forms are wire-identical to before, so
    pre-feature reports load byte-for-byte unchanged. A form a *newer* version
    added loads as a rectangle while preserving the original name in
    `unknownForm`, and re-saves it — a lossless round-trip. A deliberate pick
    clears the preserved name.
  - The section label and all eight form names are localized in en/de/tr; each
    thumbnail is a keyboard-reachable button exposing its localized accessible
    name and selected state.

- **Editable report Name in Report properties.** When the report is selected, the
  Properties panel now leads with a primary **Name** field that edits the report
  (template) name through the existing `JetReportDesignerController.rename` — one
  undoable step, kept in sync with the toolbar's inline rename. A blank entry
  reverts, so the report always keeps a name. No new public surface or schema
  change; the label is localized in en/de/tr.

- **Editable paper type & margins in Report properties (spec 018-paper-margin-properties).**
  The Properties panel's **PAGE** section is now an editable, Microsoft
  Office–style page setup: a live page-sample thumbnail (a proportional sheet
  with margin guides), a **paper-type** picker (A4 / A3 / A5 / Letter / Legal /
  Custom, recognized by name in either orientation), a **Portrait | Landscape**
  toggle, **Custom** width/height fields (shown for a custom size), a margin
  **preset** picker (Normal / Narrow / Wide / None) and editable per-side
  left/top/right/bottom fields.
  - New public surface is additive and minimal:
    `JetReportDesignerController.setPageFormat(PageFormat)` (one undoable,
    notifying step that clamps to a usable page so the content area stays
    positive), plus `PageFormat.copyWith(...)` and `JetEdgeInsets.copyWith(...)`
    on the existing immutable value types. Paper/margin presets, recognition,
    the clamp, and the page-preview are private.
  - Canvas, preview, and export all read the one `template.page`, so a size /
    orientation / margin change shows identically in all three (WYSIWYG). Preset
    identity and orientation are **derived for display, never serialized** —
    `kReportSchemaVersion` stays **1**, no migration, old templates load
    unchanged. New labels are localized in en/de/tr.

- Added `JetReportWorkspace`: a keep-alive designer↔preview workspace. Both
  views stay mounted so switching modes is instant (no canvas re-record), and
  the preview renders behind a loading indicator (`ShadProgress`, overridable
  via `loadingBuilder`) so the first large-data render gives visible feedback
  instead of a frozen frame. A failed render is reported via
  `FlutterError.reportError` and clears the indicator. Export/print receive the
  current `RenderedReport`.

- **Unified context-switching toolbar (spec 017-unified-toolbar).** The designer
  and the report preview now read as *one toolbar that changes by context*: a
  single shared shell renders the report name (left) and a two-segment
  **Designer | Preview** mode switch (center), identical in both modes, while
  each mode fills the right slot with its own actions.
  - The mode switch reuses the existing switch events — selecting **Preview**
    from the designer fires `onPreviewRequested`, selecting **Designer** from
    the preview fires `onBack` — so existing hosts get the switch for free and
    the host keeps ownership of the actual swap. The inactive segment is enabled
    only when its callback is wired. Each segment carries an expressive glyph
    (a drafting **pencil-ruler** for Designer, a **page-under-magnifier** for
    Preview), and the leading file icon is the same in both modes so the shared
    region reads as one bar.
  - The report name is shown **read-only** in the toolbar (the inline-rename
    affordance is no longer surfaced there). Renaming stays available to hosts
    through `JetReportDesignerController.rename(String)` (a single undoable step)
    and the `JetReportPreview.onRename` hook, to be surfaced from the host's own
    UI.
  - The designer's right slot leads with the **Open / Save** file actions
    (ahead of the editing commands); **Export** is offered only in the preview,
    where the rendered artifact exists.
  - New localized chrome (`modeDesigner`, `modePreview`) in en/de/tr. No
    render-path or serialization change: `kReportSchemaVersion` stays `1` and
    report goldens are byte-identical.

- **Clipboard operations in the designer UI (spec 016-clipboard-operations).**
  The designer's cut/copy/paste — until now keyboard-only — become
  mouse-reachable through two new surfaces, both built into `JetReportDesigner`
  with zero host wiring:
  - A fenced **Cut / Copy / Paste** icon-button group joins the top bar, right
    after Undo/Redo. Cut/Copy enable when elements are selected; Paste enables
    the moment the clipboard has content. Tooltips are localized (en/de/tr) and
    carry the platform keyboard shortcut (⌘ on Apple, Ctrl+ elsewhere).
  - A net-new **canvas context menu** (Cut, Copy, Paste, Duplicate, Delete) opens
    on right-click. It resolves selection before opening — right-clicking an
    unselected element selects it, a multi-selection is preserved, and an empty
    right-click never deselects — and shows each item's shortcut hint.
  - Both surfaces invoke the existing controller clipboard ops (no second
    clipboard) and read the same two predicates, so they can never diverge. Two
    additive controller getters, `canCopy` and `canPaste`, mirror the existing
    `canUndo`/`canRedo` idiom; `copy()` now notifies listeners (without creating
    an undo entry) so Paste re-enables immediately after a mouse Copy.
  - Invocation surfaces only — no model, codec, `schemaVersion`, or render-path
    change, so saved files and preview/export/print output stay byte-identical
    and the keyboard shortcuts keep working unchanged.

- **Grid & snap helper tools (spec 015-grid-snap-tools).** The two remaining
  design-canvas helper tools now behave as their top-bar icons promise:
  - A light **5 mm alignment grid** is drawn as backmost design-time chrome on
    each band, registered to the band's content origin so every drawn line lands
    exactly on a snap target (true WYSIWYG). It is **on by default**, toggled by
    the existing grid button, stays page-registered through zoom/pan, and
    adaptively coarsens then hides when zoomed far out so it never smears into a
    solid fill.
  - The grid is design-time chrome only — like the rulers it never flows through
    the render pipeline, so preview, export, print, and saved templates are
    completely unaffected (no model, codec, or `schemaVersion` change).

- **Canvas rulers (spec 014-canvas-rulers).** The design canvas now shows a
  horizontal ruler along the top and a vertical ruler down the left, calibrated
  in **millimetres** from the page's physical top-left corner (0,0):
  - Marks stay locked to true page positions across the full zoom range and while
    panning, with an adaptive "nice-step" labelled interval (1/2/5 ladder) so
    labels never crowd or vanish, plus finer unlabelled subdivisions. Labels are
    localized to the active locale's number grouping (en/de/tr).
  - A thin marker tracks the pointer on both rulers, and the current selection's
    **union bounding box** is highlighted as one combined span per ruler
    (single element, multi-selection, or band), updating on move/resize and
    clearing on deselect.
  - Rulers are shown/hidden by the existing top-bar ruler toggle and are **on by
    default**. Two methods are added to `JetReportDesignerController`,
    `rulersEnabled` / `setRulersEnabled`, mirroring the grid/snap pair; ruler
    visibility is a per-session view preference and is never serialized.
  - Rulers are design-time chrome only — they never flow through the render
    pipeline, so preview, export, and saved templates are completely unaffected
    (no model, codec, or `schemaVersion` change).

- **Simplified label value & format properties (spec
  013-label-value-format).** The label (text element) Properties panel now has a
  single **Value** field in place of the separate Text and Binding inputs, plus a
  new **Format** field:
  - The Value field recognizes three forms — a whole-value `[fieldName]` simple
    binding, a `{ … }` advanced template mixing `[field]` tokens, literal text,
    and functions (e.g. `{upper[name]}`, `{[firstName] [lastName]}`), and
    otherwise literal text (with a `\` escape for literal brackets/braces). It
    shows a stored binding exactly as the canvas token, and presents a
    legacy/out-of-grammar expression read-only so it is never lost. Bindings stay
    single-sourced in `TextElement.expression`; the template is a pure
    string↔string projection over the existing expression parser (no parallel
    render path).
  - A new optional `TextElement.format` (additive, no schema-version bump) — an
    ICU number/date pattern applied to the resolved value at render time through
    a shared `applyJetFormat` helper (the same logic behind the `FORMAT`
    function, so they cannot drift). The Format field offers seven quick-pick
    presets (None, Integer, Decimal, Currency, Percent, Date, Date & time); a
    pattern that does not fit the value or is malformed falls back to the
    unformatted value.
  - A binding to a field absent from the active data source renders a localized
    `#ERROR` token in schema-aware contexts (designer/preview). `RenderOptions`
    gains two additive fields — `knownFields` (`Set<String>?`, the data source's
    declared field names) and `unresolvedFieldToken` (default `#ERROR`); when
    `knownFields` is supplied, a binding outside it renders the token, otherwise
    behavior is unchanged. The token is a plain string so the headless render
    layer stays Flutter-free; a host with a `BuildContext` passes a localized
    value.
  - New Properties-panel strings localized en/de/tr with English fallback.
- **Export & print — PDF, PNG, and the system print dialog (spec
  012-export-support).** The same `RenderedReport` the preview displays now
  turns into shareable artifacts; one render feeds every target. New public
  surface from the single entry point:
  - `JetReportExporter` — stateless `const` facade. `toPdf(report)` returns
    in-memory PDF bytes: every page in order at the template's true physical
    size (PostScript points), real selectable/searchable text placed at the
    pre-measured baselines with the measuring fonts embedded, and images at
    the preview's `computeImageFit` geometry. Byte-deterministic: identical
    rendered inputs produce byte-identical files (fixed document ID, no
    timestamp metadata). `pageToPng(report, i, {scale})` rasterizes one page
    through the preview's own paint path at exactly
    `round(page × scale)` pixels; out-of-range pages throw `RangeError`,
    non-positive scales throw `ArgumentError`.
  - `JetReportPrinter` — `printReport(report, {jobName})` exports the PDF
    and presents the operating system's print dialog at the template's true
    page size (the one sanctioned exception to the library's headlessness).
    Returns `false` on user cancellation (not an error); throws
    `PrintUnavailableException` where the platform cannot print. The dialog
    sits behind the injectable `PrintDialogPresenter` seam, so hosts and
    tests can substitute it without platform channels.
  - `JetReportPreview` gains optional `onExportPdf` / `onPrint` callbacks:
    each non-null callback adds a localized (en/de/tr), keyboard-operable
    toolbar action; with both null the widget is unchanged from 011. The
    library only invokes the callback — saving/sharing stays host code.
  - Content problems (empty dataset, unresolved image, failed expression)
    never fail an export: artifacts show the same fallbacks as the preview,
    with `report.diagnostics` untouched.
  - New dependencies: `pdf` (pure-Dart PDF generation), `printing` (system
    print dialog; confined to the print seam), `image` (raster decoding for
    PDF embedding). The playground demonstrates save-as-PDF (`file_selector`)
    and print end-to-end from the preview toolbar; sandboxed macOS hosts
    need the `com.apple.security.print` entitlement to print.

- **Render engine — data-filled paginated preview (spec 011-render-export).**
  A host hands a designed template plus actual data to a public engine facade
  and gets a lazily-paginated, WYSIWYG, on-screen preview. New public surface
  from the single entry point:
  - `JetReportEngine` — `render(template, source, {options})` composes the
    fill pass (expression evaluation, master/detail iteration,
    variables/aggregates) with the layout pass (pagination, repeated page
    chrome, `PAGE_NUMBER`/`PAGE_COUNT`). Never throws on malformed data;
    deterministic over (template, data, parameters, locale).
  - `RenderOptions` — per-render parameter values plus an **explicit
    formatting locale** (number/date/currency formatting follows it — never
    the app UI locale or the ambient `Intl.defaultLocale`).
  - `RenderedReport` / `RenderedPage` — the render output IR: an exact
    `pageCount` resolved by a cheap boundary-only pass, **lazy** per-page
    frame construction with caching (the first page renders without
    materializing the rest), and merged ordered `diagnostics`. Structured so
    a future export slice consumes it without rework.
  - `JetReportPreview` — a read-only paginated viewer with a top toolbar
    styled to match the designer: the report name as the title, bounded
    prev/next + arrow-key navigation with a localized "page X of N" indicator
    (en/de/tr with English fallback), a zoom group (out / tap-% to fit / in;
    the page scrolls when zoomed past fit-to-width), and an optional back
    button (`onBack`). Pages paint through the same `paintFrame`/`CanvasPainter`
    pipeline as the designer surface. `RenderedReport` carries the source
    template's name as `title` for the toolbar.
  - `JetReportDesigner(onPreviewRequested:)` — the top bar's **Preview**
    action is now wired to this host callback (receiving the live template),
    mirroring `onSaveRequested`/`onOpenRequested`; it renders disabled when
    unwired. The playground opens its rendered-invoice preview from it.
  - The full data-source API is now public: `JetDataSource`,
    `JetInMemoryDataSource`, `JetJsonDataSource`, `JetObjectDataSource<T>`,
    `DataSet`, `DataRow` — the same logical dataset renders byte-identically
    through all three implementations, including nested collections.
  - Diagnostics are now public: `Diagnostic`, `DiagnosticSeverity`,
    `ReportDiagnostics` (which gains `add` for merging). Unknown fields,
    missing parameters, expression errors, empty datasets, and URL-only
    images each yield a specific diagnostic plus a best-effort render.
  - The fill pass now iterates **nested collections**: a detail band bound to
    a `collectionField` repeats once per child row (children bands nest to
    arbitrary depth), completing the 009 master/detail authoring seam at
    render time. Declared template parameter defaults are applied when the
    host supplies no value.
  - Internal additive seam: `ReportLayouter.layoutLazy` produces pages on
    demand; the eager `layout()` is preserved as a thin wrapper over it, so
    existing rendering output is byte-stable.
  - The playground gains a runnable **rendered-invoice** example (in-memory,
    JSON, and object-backed variants) and a Preview path that opens it.

- **Data-aware designer — Invoice MVP (spec 009-data-aware-designer).** The
  designer can now describe, display, and bind to a data source's structure
  (tokens only this iteration — values are not yet filled/rendered). New/changed
  public surface from the single entry point:
  - `JetDataSchema` — a host-supplied data-source **structure** (a named dataset
    of `FieldDef`s) attached to the designer via the new `JetReportDesigner`
    `dataSchema:` parameter. Not embedded in the saved template; bindings are
    self-describing, so a report reopened without a source still shows its tokens.
  - `FieldDef` is now public **and recursive** — a `JetFieldType.collection`
    field carries its own child `fields`, modelling master/detail (e.g. an
    invoice with a nested `lines` collection) to arbitrary depth.
  - `JetFieldType.collection` — the nested-collection field type.
  - `JetReportDesignerController` gains `setBinding` / `clearBinding` /
    `setImageField` / `createBoundElement` (element data binding) and
    `setBandCollection(bandPath, field)` (designate a band's master/detail
    collection); each is one undoable step.
  - `ReportBand` gains additive-optional `collectionField` + nested `children`
    (master/detail); they round-trip losslessly at the existing `schemaVersion`
    (no migration — pre-1.0 additive carve-out).
  - Designer UX: the **Data Source panel** renders the attached schema as an
    expandable tree (nested collections included) with a clear empty state,
    replacing the hardcoded placeholder; leaf fields drag onto the canvas to
    create a bound element; the **Properties** inspector binds an element (field
    or expression) or designates a band's collection, clears a binding, and flags
    an unresolved binding; bound elements show a design-time token through the
    shared render pipeline. All new chrome localized (en/de/tr).
  - The **playground** ships an invoice sample (`invoiceSchema` +
    `invoiceSampleTemplate`) demonstrating master/detail through the public API.
  - *Deferred:* filling/rendering real data values, exposing the fill/expression
    engine, barcode binding, and design-canvas rendering of *nested* child bands
    (the model/codec/scope support arbitrary nesting today).
- **Designer edit surface (spec 003-designer-edit-surface).** The center surface
  is now a fully interactive WYSIWYG canvas — create, select, move, resize,
  multi-select, snap, align/distribute/z-order, undo/redo, zoom/pan, inline text
  edit, model-driven panels, accessibility, localization, and a host save/open
  seam. New public surface from the single entry point:
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
  - **Open / Save are wired to the host.** The top bar gains an **Open** action
    beside **Save**; both call the new `JetReportDesigner.onOpenRequested` /
    `onSaveRequested` callbacks and render disabled when the host wired none. The
    library still performs **no** file I/O itself (FR-022) — the playground app
    implements the host side with `file_selector` + `JetReportFormat`.
  - **Accessibility.** Every interactive affordance now exposes a localized
    accessible name and a button role: each canvas element ("Text element …"),
    all eight resize handles (directional names) and the band-height handle, and
    the top-bar actions (Arrange, zoom, Open/Save). Element regions are discrete
    semantics nodes so a screen reader announces one element per stop.
  - **Localization (en / de / tr).** The Arrange menu, the Properties inspector
    labels, the Outline root, the Open action, and all the new accessible names
    are fully localized with English fallback — no raw keys or blank labels
    (SC-008).
  - **Fidelity + performance coverage.** Added design-surface goldens
    (representative elements with a selection shown, light + dark, via the shared
    render pipeline) and a 200-element multi-select drag performance smoke
    (SC-007).
  - This completes the spec-003 designer edit surface; only the merge-gate
    house-keeping remains.
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

### Changed

- **Grid snap step is now 5 mm (was 8 pt)** (spec 015-grid-snap-tools) so the
  snap grid coincides with the new visible grid and the millimetre rulers. This
  affects **new** interactive placements only; stored report coordinates are
  untouched.
- **Grid visibility is decoupled from grid snapping** (spec 015-grid-snap-tools).
  The grid button now controls only whether the grid is **drawn**; snapping
  (grid + sibling + band) is governed solely by the magnet/snap toggle. Elements
  snap to the 5 mm grid even when the grid is hidden, and all four grid/snap
  on-off combinations are valid. `JetReportDesignerController.gridEnabled` /
  `setGridEnabled` keep their signatures but now mean *visibility only*.
- **Snapping now defaults to off.** The grid is still shown by default, but the
  magnet/snap toggle starts off — switch it on to snap. (`snapEnabled` defaults
  to `false`.)
- **Top bar: the ruler toggle moved to the left of the view-toggle group**, so
  the order is now ruler, grid, snap.

- **Designer: double-tap now opens the Properties inspector (in-place editing
  removed).** Double-tapping anything on the canvas — an element, a band's
  empty area, or the report (paper off any band) — selects it, brings the
  right panel to the Properties tab (expanding the collapsed narrow-layout
  overlay first when needed), and moves keyboard focus into the most relevant
  field: Text for a text element, X for any other element, height for a band.
  The report inspector is read-only, so its double-tap simply brings the pane
  forward. The inline double-click text editor is gone; the Properties panel
  is the single text-editing surface. New `JetReportDesignerController` members
  back this:
  `requestPropertiesFocus()` raises a one-shot UI intent,
  `pendingPropertiesFocus` peeks at it, and `takePropertiesFocus()` consumes
  it (the designer chrome wires these automatically; hosts may call
  `requestPropertiesFocus()` to deep-link their own UI into the inspector).

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
