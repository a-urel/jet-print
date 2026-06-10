# Data Model: Export Support (012)

This slice adds **no persisted data and no template schema change** (FR-012). Every entity
below is an in-memory runtime type. Arrows show dependency direction (all point inward,
Constitution II).

```text
JetReportPreview ──callbacks──▶ host ──▶ JetReportExporter ──▶ paintFrame ──▶ PdfPainter ──▶ package:pdf
        │                        │              │                                (rendering seam, pure Dart)
        │                        │              └──▶ PageRasterizer ──▶ CanvasPainter ──▶ dart:ui (PNG)
        ▼                        ▼
  RenderedReport (011)    JetReportPrinter ──▶ JetReportExporter.toPdf ──▶ presenter seam ──▶ package:printing
                            (print seam)                                     (system dialog)
```

## Existing entities consumed unchanged (from 011)

| Entity | Source | Role in export |
|--------|--------|----------------|
| `RenderedReport` | `src/rendering/engine/rendered_report.dart` | The **single shared input** to preview, PDF, PNG, and print (FR-001). `pageCount` is exact; `pageAt(i)` builds+caches frames on demand — export iterates `0..pageCount-1`, materializing all pages (FR-011). `title` seeds the default print job name. |
| `RenderedPage` | same | One page: `index` + `frame`. |
| `PageFrame` | `src/rendering/frame/page_frame.dart` | Backend-agnostic display list: `page` (PageFormat) + ordered `primitives`. The WYSIWYG contract between layout and *every* paint backend. |
| `FramePrimitive` (sealed: `TextRunPrimitive`, `ImagePrimitive`, `LinePrimitive`, `RectPrimitive`, `PathPrimitive`) | `src/rendering/frame/primitive.dart` | What `PdfPainter` must draw. `TextRunPrimitive` carries pre-measured `TextLine`s (text, width, top, baseline, height) — backends place lines at exact baselines and never re-wrap (FR-003/004). `ImagePrimitive.bytes` are host-resolved encoded bytes (PNG/JPEG); unresolved images never reach the frame — the layouter already substitutes the shared placeholder primitives, so PDF/PNG show the same fallback as the preview for free (FR-010, SC-007). |
| `PageFormat` | `src/domain/page_format.dart` | Width/height in **points (1/72 in)** — the same unit PDF uses natively, so physical fidelity (FR-008) is a unit-preserving pass-through (A4 template → 595.28×841.89 pt MediaBox). |
| `FontRegistry` | `src/rendering/text/font_registry.dart` | `bytesFor(family, weight, italic)` returns the same TTF bytes that drove measurement; `PdfPainter` embeds them (FR-005) and `CanvasPainter` loads them — measure/draw/embed all share one byte source. |
| `ReportPainter` + `paintFrame()` | `src/rendering/paint/report_painter.dart` | The backend abstraction and its exhaustive walk (`prepare → beginPage → primitives → endPage`). `PdfPainter` is its third implementation (after `CanvasPainter` and test fakes); a new primitive type remains a compile error until every backend handles it. |
| `computeImageFit` | `src/rendering/paint/image_fit.dart` | Shared src/dst rect math; PDF image placement matches the preview pixel-for-point (FR-003 scenario 4). |
| `ReportDiagnostics` / `Diagnostic` | `src/rendering/fill/report_diagnostics.dart` | Render-time diagnostics ride along unchanged; export adds **no** new diagnostics channel — content problems are already baked into the frame as fallbacks, and invalid *requests* are thrown errors (below). |

## New entities

### `JetReportExporter` (public — the export capability, FR-001/002/006)

Stateless, `const`-constructible facade in `src/rendering/export/jet_report_exporter.dart`.

| Member | Type | Notes |
|--------|------|-------|
| `toPdf(RenderedReport report)` | `Future<Uint8List>` | Whole document, pages in order (FR-002). Single awaitable (no progress/cancel this slice — additive named params can arrive later without breaking). Deterministic bytes (FR-007). |
| `pageToPng(RenderedReport report, int pageIndex, {double scale = 1.0})` | `Future<Uint8List>` | One page as PNG (FR-006). Pixel dims = `round(page.width×scale) × round(page.height×scale)` (SC-006). All pages = host iteration in page order. |

**Validation rules**:
- `pageIndex ∉ [0, pageCount)` → `RangeError.range` (the same structured error
  `RenderedReport.pageAt` already throws — one vocabulary, FR-010, edge case "out-of-range page").
- `scale <= 0` → `ArgumentError.value`.
- Empty report (`pageCount ≥ 1` always — the layouter emits at least one page) exports the
  static pages the preview shows; never a zero-page artifact (edge case "empty report").

**Internal collaborators** (not public): `PdfPainter` (per export, accumulates pages into
one fixed-metadata `PdfDocument`), `PageRasterizer` (records the frame through
`CanvasPainter` at `scale`, encodes PNG via `dart:ui`), a per-export
`FontRegistry()..registerDefault()` exactly as the preview constructs one.

### `PdfPainter` (internal — `ReportPainter` backend, pure Dart)

`src/rendering/export/pdf_painter.dart`. One instance per `toPdf` call; owns the
`PdfDocument` with **fixed metadata** (zeroed/fixed creation date + document ID — see
[research.md](research.md) §2) so identical input → identical bytes (FR-007).

| Responsibility | Mechanism |
|----------------|-----------|
| `beginPage(format)` | New PDF page, MediaBox = `format.width × format.height` pt (FR-008); installs the top-left→bottom-left y-flip transform (PDF origin is bottom-left). |
| `drawTextRun` | For each pre-measured `TextLine`: resolve the variant via `FontRegistry`, embed TTF once per variant per document (FR-005), draw the line's text at the same aligned x (`left/center/right` math identical to `CanvasPainter`) and exact `bounds.y + line.top + line.baseline` baseline — real text objects, selectable/searchable (FR-004). |
| `drawImage` | Decode `ImagePrimitive.bytes` once in `prepare` (pure Dart), embed, place via `computeImageFit` src/dst rects with clipping — same geometry as the preview. |
| `drawLine` / `drawRect` / `drawPath` | Direct mapping to PDF stroke/fill operators; same color/strokeWidth semantics as `CanvasPainter` (fill and stroke emitted as in the canvas backend: fill first, then stroke). |

### `PageRasterizer` (internal — PNG backend over the existing canvas pipeline)

`src/rendering/paint/page_rasterizer.dart` (joins `canvas_painter.dart` on the declared
dart:ui allowlist). Records `paintFrame(frame, CanvasPainter(canvas, fonts))` into a
`ui.Picture` with a `scale` canvas transform, `Picture.toImage(round(w×scale), round(h×scale))`,
encodes `ImageByteFormat.png`. Identical paint path to the preview ⇒ identical pixels
(US2 acceptance 1); deterministic for identical input on a given engine (the same property
the golden tests rely on).

### `JetReportPrinter` (public — the print capability, FR-009a)

`src/print/jet_report_printer.dart` — the **only** library code touching a platform
channel, behind a swappable seam (Tech-standards).

| Member | Type | Notes |
|--------|------|-------|
| `JetReportPrinter({PrintDialogPresenter? presenter})` | const ctor | `presenter` defaults to the `package:printing` implementation; injectable for tests and host substitution. |
| `printReport(RenderedReport report, {String? jobName})` | `Future<bool>` | Exports via `JetReportExporter.toPdf`, presents the system dialog at the report's page size; `jobName` defaults to `report.title` (or a fixed fallback). Returns whether the job was sent (false = user cancelled — not an error). |

### `PrintDialogPresenter` (public — the swappable print seam)

```dart
typedef PrintDialogPresenter = Future<bool> Function(
  Uint8List pdfBytes, {
  required String jobName,
  required double pageWidthPt,
  required double pageHeightPt,
});
```
The default implementation delegates to `printing`'s layout callback and checks
availability first.

### `PrintUnavailableException` (public — structured print failure, FR-009a)

`implements Exception`; carries a message naming the platform/cause. Thrown by
`printReport` when the platform reports no print support (never a crash, never a silent
no-op — US3 acceptance 4). Cancellation is **not** an exception (returns `false`).

### `JetReportPreview` additions (public — FR-015)

| New member | Type | Behavior |
|------------|------|----------|
| `onExportPdf` | `VoidCallback?` | Null ⇒ no export button (011 behavior bit-preserved, US4 acceptance 4). Non-null ⇒ toolbar export action (icon + localized tooltip/accessible name, keyboard-operable) invoking the callback. The **host** owns what export means (save dialog, share sheet) — the library performs no I/O (FR-015). |
| `onPrint` | `VoidCallback?` | Same pattern for print; the playground's callback delegates to `JetReportPrinter`. |

New ARB keys (en/de/tr + English fallback, FR-014): `previewExport` ("Export as PDF"-class
tooltip/label), `previewPrint` ("Print"-class tooltip/label).

## State transitions

None persisted. Per-export lifecycle: `RenderedReport` (existing, possibly partially
materialized) → exporter materializes pages `0..N-1` via `pageAt` (cache-warm pages reused;
concurrent/repeat export safe because frames are immutable and the cache returns identical
instances — edge case "concurrent/repeat export") → artifact bytes returned; the exporter
holds no state between calls.
