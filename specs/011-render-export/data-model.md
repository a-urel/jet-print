# Phase 1 Data Model — Render Report (JetReportEngine Facade)

This slice introduces **no persisted schema** (FR-016) — every entity below is **runtime / in-memory**. Entities are grouped by whether they are **new** (this slice) or **promoted** (existing `src/` types becoming public unchanged). Field names are indicative; the authoritative signatures live in [contracts/render-engine-api.md](contracts/render-engine-api.md).

## New entities (this slice)

### JetReportEngine
The public facade. Stateless orchestrator over the existing `ReportFiller` + `ReportLayouter`.

| Member | Type | Notes |
|--------|------|-------|
| `render(template, source, {options})` | `RenderedReport` | Runs fill → lazy layout; merges diagnostics; FR-001/FR-002. Holds no rendering logic. |

- **Relationships**: consumes a `ReportTemplate` (existing public model) + a `JetDataSource` (promoted) + `RenderOptions`; produces a `RenderedReport`.
- **Validation / behavior**: never throws on malformed *data* — problems surface as diagnostics (FR-013/FR-014). Deterministic over (template, data, params, locale) (FR-010).

### RenderOptions
Per-render inputs, separate from the template.

| Field | Type | Rules |
|-------|------|-------|
| `parameters` | `Map<String, Object?>` | Host-supplied parameter values keyed by name (FR-012). Unsupplied required params → diagnostic + defined default (SC-007). |
| `locale` | `Locale` | Explicit per-render locale for number/date/currency formatting (FR-012a). MUST NOT fall back to the app UI locale. Default: a documented neutral locale. |

- **Relationships**: passed to `JetReportEngine.render`; threaded into fill + layout formatting context.

### RenderedReport
The engine output — the input to both the preview and a future export slice (FR-020).

| Member | Type | Notes |
|--------|------|-------|
| `pageCount` | `int` | Total pages; resolved by the cheap boundary pass (research §2). Drives "page X of N" and `PAGE_COUNT`. |
| `pageAt(index)` | `RenderedPage` | **Lazy**: builds and caches the page's frame on demand (FR-021). First page built without constructing the rest. |
| `diagnostics` | `ReportDiagnostics` | Merged fill + layout diagnostics, in order (FR-013). |

- **Relationships**: holds the template's `PageFormat`; yields `RenderedPage`s.
- **State**: page frames are built on first access and cached; re-access returns the identical frame (determinism, SC-004).
- **Validation**: `pageAt` index in `[0, pageCount)`.

### RenderedPage
One paginated unit.

| Field | Type | Notes |
|-------|------|-------|
| `index` | `int` | Zero-based page index. |
| `frame` | `PageFrame` | The existing backend-agnostic positioned-primitive frame (incl. repeated page header/footer with resolved `PAGE_NUMBER`/`PAGE_COUNT`). |

- **Relationships**: thin wrapper over the existing `PageFrame`; consumed by the preview's painter and (later) an export backend — no IR rework needed (FR-020).

### JetReportPreview (widget)
The on-screen, read-only paginated viewer (FR-008/FR-009).

| Aspect | Behavior |
|--------|----------|
| Source | A `RenderedReport` (+ initial page index). |
| Navigation | Prev/next page; bounded at first/last (clarification Q3). |
| Indicator | "Page X of N" (localized). |
| Sizing | Fit-to-width. |
| Paint | Drives the **shared** `paintFrame`→`CanvasPainter` over the current `RenderedPage.frame` (Constitution IV; FR-009). |
| A11y / i18n | Keyboard-operable, accessible names (FR-018); chrome localized en/de/tr + English fallback (FR-017). |

- **State transitions**: `currentPage` ∈ `[0, pageCount)`; prev/next move by one and request `pageAt` (lazy build). No edit/zoom/annotation state (out of scope).

## Promoted entities (existing `src/`, now public — unchanged code)

### JetDataSource (abstract) + implementations
The host's supply of records, including nested collections for master/detail (FR-011).

| Type | Role |
|------|------|
| `JetDataSource` | Abstract: `open([params]) → DataSet`. |
| `JetInMemoryDataSource` | Rows as `List<Map<String, Object?>>` (+ optional explicit/inferred schema). |
| `JetJsonDataSource` | JSON array-of-objects → delegates to in-memory. |
| `JetObjectDataSource<T>` | `List<T>` + schema + field-extraction fn; lazy per-row mapping. |
| `DataSet` (abstract) | Forward-only cursor: `moveNext()`, `current`, `fields`, `close()`. |
| `DataRow` | Immutable row snapshot: `field(name)`, `hasField(name)`. |

- **Relationships**: a `JetDataSource` opens a `DataSet` (cursor) of `DataRow`s typed by `FieldDef`s; a `collection` `FieldDef` carries child rows (master/detail). `FieldDef`/`JetFieldType` already public (009).
- **Parity invariant (SC-006)**: the same logical dataset supplied via any of the three implementations MUST render identical output.

### Diagnostics
Structured, non-fatal render problems (FR-013).

| Type | Fields |
|------|--------|
| `DiagnosticSeverity` | `info` \| `warning` \| `error`. |
| `Diagnostic` | `severity`, `message`, `elementId?` (identifies the affected element/band). |
| `ReportDiagnostics` | Ordered collection with `.entries` + severity helpers. |

- **Relationships**: produced by fill + layout; surfaced on `RenderedReport.diagnostics`.

## Entities consumed unchanged (already public)

`ReportTemplate`, `ReportBand`, `ReportElement` (+ subtypes), `ReportGroup`, `ReportParameter`, `ReportVariable` (`JetCalculation`, `VariableResetScope`), `PageFormat`, the `JetImageSource` family, geometry/style value types, and `JetReportFormat`. No schema change (FR-016).

## Lifecycle (render → preview)

```text
host: ReportTemplate (designed) + JetDataSource (data) + RenderOptions (params, locale)
        │
        ▼
JetReportEngine.render
        │  ReportFiller.fill ───────────► FilledReport (+ fill diagnostics)   [eager data, lightweight]
        │  lazy layout seam (boundary pass) ► page breaks + pageCount + PAGE_COUNT
        ▼
RenderedReport { pageCount, pageAt(i)→RenderedPage[lazy frame build], diagnostics(merged) }
        │
        ▼
JetReportPreview ── paintFrame(page.frame) ► CanvasPainter ► on-screen page  (prev/next, X of N, fit-to-width)
```

## Invariants

- **WYSIWYG (Constitution IV / FR-009)**: preview frames come from the same `paintFrame`/`CanvasPainter`/`PageFrame` path as the designer — no parallel draw code.
- **Lazy first page (FR-021/SC-009)**: `pageAt(0)` builds one page's frame; building it MUST NOT construct frames for other pages.
- **Lazy ≡ eager**: `RenderedReport.pageAt(i).frame` equals the i-th frame from the eager `layout()` wrapper (seam-equivalence; guards Constitution IV + SC-004).
- **Determinism (FR-010/SC-004)**: identical (template, data, params, locale) → byte-identical frames.
- **Headless (FR-015/FR-012b)**: no filesystem/print/network I/O; image bytes are host-supplied; URL-only image → placeholder + diagnostic.
- **No schema change (FR-016)**: templates load through the existing format; `schemaVersion` stays `1`.
