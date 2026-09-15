# Architecture

How a report definition becomes pixels, and where you extend it without editing
the core. Read [`../AGENTS.md`](../AGENTS.md) first for the rules this structure
exists to uphold.

## The pipeline

```text
ReportDefinition  +  JetDataSource  +  RenderOptions
        │
        ▼  ReportFiller            rendering/fill/
   FilledReport                    expressions evaluated, master/detail walked,
        │                          variables + aggregates accumulated,
        │                          visibility resolved, diagnostics collected
        ▼  ReportLayouter          rendering/layout/
   RenderedReport                  paginated LAZILY — pageAt(i) materializes
        │                          one page; page chrome repeated; PAGE_NUMBER
        │                          and PAGE_COUNT substituted per page
        ▼  FrameBuilder            rendering/frame/
   PageFrame                       ◄── THE WYSIWYG CONTRACT
        │                          a flat, immutable display list of positioned
        │                          FramePrimitives, pure-Dart geometry, each
        │                          tagged with its originating element id
        │
        ├──► CanvasPainter / ReportPainter  ──► preview, page thumbnails
        ├──► DesignTimeFrame                ──► the interactive design canvas
        ├──► PageRasterizer                 ──► PNG
        └──► PdfPainter                     ──► PDF (selectable text, embedded fonts)
```

`PageFrame` is the keystone. Every surface that shows a page — canvas, preview,
thumbnail rail, PNG, PDF — consumes the *same* frame. That is the mechanism
behind "one paint path": WYSIWYG is not maintained by discipline across five
painters, it holds by construction because there is only one thing to paint.

When you are tempted to draw something directly on a surface, the right move is
almost always to emit a primitive instead.

`JetReportEngine` is a thin, `const`, stateless facade over the fill and layout
passes. It owns no rendering logic. Two guarantees worth knowing: it never
throws on malformed data — unknown fields, missing parameters and unresolvable
images degrade and surface on `RenderedReport.diagnostics` — and it is
deterministic for a given (definition, data, parameters, locale).

## The layers

### `domain/` — the model

The serializable report tree, pure Dart, no Flutter UI. `ReportDefinition` holds
page furniture (header, footer, watermark) plus a `ReportBody` whose `root` is a
`DetailScope` tree of bands, groups and nested scopes. Elements are
`ReportElement` subclasses with bounds, styles and optional expressions.

Two invariants live here:

- **`validate()` is the author-time diagnostic pass.** It catches structural
  mistakes — a heading band sitting in a per-row slot, a group with no source, a
  nested scope that cannot aggregate. Historically the *bugs it would have
  caught shipped anyway*, because nothing called it on the sample reports. If
  you add a demo or fixture, validate it.
- **Unknown types round-trip byte-for-byte.** `UnknownElement` and
  `UnknownScopeNode` preserve the raw JSON of a node written by a newer build.
  Moving, renaming, resizing or hiding one must not rewrite the preserved map.

`copy_support.dart` defines the thunk convention used across the tree: omit a
parameter to keep a value, pass `() => null` to clear, `() => v` to set.

### `expression/` — the `{...}` language

Lexer → parser → AST → evaluator, plus a function registry, aggregate support
and formatting. Pure Dart. Inline aggregates like `{SUM([total])}` are sugar:
`expandAggregates(def)` rewrites them into hidden report variables before the
fill pass ever runs, so the engine sees only ordinary variables.

The one scope rule that surprises people: report variables aggregate over
**master rows only**. Totals over a nested collection come from that scope's own
footer or from published `ScopeTotal` roll-ups injected into the parent as
fields.

### `data/` — the data seam

`JetDataSource` is the host-facing interface; `JetInMemoryDataSource`,
`JetJsonDataSource`, `JetObjectDataSource` and `JetPagedDataSource` implement it.
A `JetDataSchema` of `FieldDef`s describes shape; a `FieldDef` may itself be a
`collection`, which is how master/detail works. `DataSet` is the cursor yielding
`DataRow`s.

`JetPagedDataSource` streams pages lazily, but note the engine still *fills*
eagerly — a paged source bounds memory at the source, not through the pipeline.

### `rendering/` — fill, layout, paint

- `fill/` — `report_filler.dart` is the heart: binds data, walks master/detail,
  accumulates variables, applies visibility. `diagnostic_budget.dart` caps
  diagnostics so a pathological report cannot exhaust memory.
- `layout/` — `report_layouter.dart` paginates; `band_measurer.dart` measures.
- `frame/` — the `PageFrame` / `FramePrimitive` display list.
- `paint/` — `canvas_painter.dart` draws a frame to a `ui.Canvas`;
  `page_rasterizer.dart` produces PNG.
- `export/` — `pdf_painter.dart` draws the same frame into a PDF.
- `text/` — font registry, metrics, measurement, underline geometry, and the
  bundled default font data.
- `crosstab/` — `crosstab_planner.dart` plans pivot grids into bands.
- `elements/` — per-element renderers and the renderer registry.

`report_filler.dart` and `report_layouter.dart` are large (946 and 764 lines) and
deliberately so: they are cohesive algorithms, and splitting them has been tried
and hurts. Don't "tidy" them without a reason beyond size.

### `designer/` — the interactive surface

- `controller/` — `JetReportDesignerController` plus a command layer with
  undo/redo. Commands subclass `ElementEditCommand<E>` where they can.
- `canvas/` — the design surface, hit-testing, selection chrome, tunables.
- `layout/` — the shell: toolbox, outline panel, properties panel and its
  per-type inspectors.
- `preview/` — paginated preview and the page thumbnail rail.
- `interaction/` — pointer, keyboard and touch handling.
- `l10n/` — ARB sources for en/de/tr and the generated delegate.
- `template/` — value-template compilation for bound tokens.

Four files here are split across `part` files with `extension`s. See the trap
list in `AGENTS.md` before editing them.

### `print/` — one file

`JetReportPrinter`, an injectable seam so the rendering core stays
platform-agnostic and printing is testable without a printer.

## Extension points

These exist so new capability lands without editing the core. Use them.

| To add… | Register with | Notes |
|---|---|---|
| A new element type's persistence | `ElementCodecRegistry.register(typeKey, codec)` | `domain/serialization/element_codec.dart`. Last-write-wins, so a consumer can override a built-in. |
| A new element type's appearance | `ElementRendererRegistry.register(typeKey, renderer)` | `rendering/elements/element_renderer_registry.dart`. Unregistered types fall back to the Unknown placeholder rather than crashing. |
| A third-party encoder or backend | A single adapter file | The `package:barcode` seam is the model: exactly one file imports it, and a test enforces that. |
| Per-element host behavior at print time | `RenderOptions.onElementPrint` | Fires at the emit seam for preview, export and print. It can transform or suppress an element but **cannot change its height** — the emitted box is already measured. |

`test/rendering/elements/persisted_extension_test.dart` proves a custom element
type can be added with zero edits to library `src/`. If a change would break
that test, the extension point is not doing its job.

## Public API

`lib/jet_print.dart` is the only door — 168 lines of nothing but exports and the
documentation of why each is public. Note the controller's command families
(`CtrlSelection`, `CtrlElementEdit`, `CtrlBands`, …) are exported explicitly:
they are public `extension`s on a public class, and an unexported extension is
silently uncallable through the barrel even though it compiles fine inside the
package.
