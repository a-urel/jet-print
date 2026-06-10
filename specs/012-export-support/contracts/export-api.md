# Contract: Export & Print API (012)

The authoritative public-surface and behavior contract for the export slice. Everything
here is reachable from `package:jet_print/jet_print.dart` and nothing else is added to the
public surface. Types from 011 (`RenderedReport`, `RenderedPage`, `JetReportPreview`) are
referenced, not redefined.

## 1. Public surface (additions)

```dart
/// Turns a rendered report into shareable artifacts (the export-side
/// counterpart of JetReportPreview). Stateless; const.
class JetReportExporter {
  const JetReportExporter();

  /// The complete report as a PDF document, pages in order.
  Future<Uint8List> toPdf(RenderedReport report);

  /// One page as a PNG image at [scale] (pixel dims = page points × scale).
  Future<Uint8List> pageToPng(RenderedReport report, int pageIndex,
      {double scale = 1.0});
}

/// Presents the system print dialog for [pdfBytes] (the swappable print seam).
typedef PrintDialogPresenter = Future<bool> Function(
  Uint8List pdfBytes, {
  required String jobName,
  required double pageWidthPt,
  required double pageHeightPt,
});

/// Prints a rendered report via the operating system's print dialog —
/// the one sanctioned exception to the library's headlessness.
class JetReportPrinter {
  const JetReportPrinter({PrintDialogPresenter? presenter});

  /// Exports [report] to PDF and presents the system print dialog.
  /// Returns true if the job was handed to the OS, false if the user
  /// cancelled. Throws [PrintUnavailableException] where printing is
  /// unsupported.
  Future<bool> printReport(RenderedReport report, {String? jobName});
}

/// Printing is not available on this platform (specific, identifiable —
/// never a crash, never a silent no-op).
class PrintUnavailableException implements Exception {
  const PrintUnavailableException(this.message);
  final String message;
}

/// JetReportPreview — NEW optional parameters (011 behavior unchanged when null):
///   VoidCallback? onExportPdf;  // non-null ⇒ export toolbar action appears
///   VoidCallback? onPrint;      // non-null ⇒ print toolbar action appears
```

## 2. Behavior contracts

### B1 — One render serves all targets (FR-001)
`toPdf`/`pageToPng`/`printReport` consume the **same** `RenderedReport` instance the
preview displays. No re-fill, no re-layout, no second render pass. Export materializes
pages via `report.pageAt(i)` for `i ∈ [0, pageCount)` regardless of what the preview has
lazily viewed (FR-011).

### B2 — PDF document (FR-002/003/004/005/008)
- Exactly `report.pageCount` pages, in page order; each page's MediaBox equals the
  template's `PageFormat` width × height in PostScript points (A4 prints as A4).
- Content is painted through the shared `paintFrame(frame, painter)` walk over the same
  `PageFrame` primitives the preview paints — geometry, styles, images, and page breaks
  match the preview page-for-page (Constitution IV: no parallel paint code).
- Text is emitted as **text objects** with embedded TTF font programs from the same
  `FontRegistry` bytes that measured the lines: selectable, searchable, extractable, and
  rendered with intended appearance on machines without the fonts installed.
- Each pre-measured `TextLine` is placed at its exact computed baseline with the same
  left/center/right alignment math as `CanvasPainter`; backends never re-wrap.
- Images are embedded from the primitive's resolved bytes and placed via the shared
  `computeImageFit` rects, clipped to bounds.

### B3 — Byte-determinism (FR-007, SC-004)
For identical `(RenderedReport-producing inputs, export options)`:
`toPdf` twice → byte-identical; `pageToPng` twice → byte-identical. All
normally-varying PDF metadata (creation/modification timestamps, document ID) is
fixed/zeroed (mechanics: [research.md](../research.md) §2). No clock, randomness, or
ambient-locale read exists anywhere in the export path. Verified by hash equality and a
pinned golden artifact.

### B4 — PNG page export (FR-006, SC-006)
- Output pixel dimensions are exactly `round(page.width × scale)` ×
  `round(page.height × scale)`; content matches the preview rendering of that page
  (same `CanvasPainter`, rasterized).
- `pageIndex` out of `[0, pageCount)` → `RangeError.range` (the structured error the
  render IR already uses). `scale <= 0` → `ArgumentError`. Never a corrupt or empty image.

### B5 — Faithful fallbacks, never diverging from the preview (FR-010, SC-007)
Recoverable content problems (unresolved image, failed expression, empty dataset) are
already materialized in the frame as the preview's placeholder/fallback primitives —
the artifact therefore shows **the same** fallback as the preview, with the render
diagnostics unchanged on `report.diagnostics`. Export never throws for content problems;
it throws only for invalid requests (B4) and print unavailability (B6).

### B6 — Print (FR-009a)
- `printReport` produces the B2/B3 PDF and hands it to the presenter with the report's
  page dimensions and a job name (`jobName` ?? non-empty `report.title` ?? `'Report'`).
- Default presenter: the `package:printing` system dialog. Platform without print
  support → `PrintUnavailableException` (specific, identifiable). User cancellation →
  returns `false` (not an error). No other file/network I/O occurs.
- The presenter is injectable: hosts/tests can substitute the dialog without platform
  channels (Tech-standards: swappable abstraction).

### B7 — Headlessness (FR-009)
`toPdf`/`pageToPng` perform no filesystem, network, or platform-channel I/O — bytes in,
bytes out. Saving/sharing is host code (playground demonstrates `file_selector`).
`printReport` is the sole sanctioned exception (B6).

### B8 — Preview actions (FR-015, FR-014)
- `onExportPdf == null && onPrint == null` ⇒ the widget tree, semantics, and goldens are
  identical to 011 (no buttons, no reserved space).
- A non-null callback adds its toolbar action: ghost icon button in the preview toolbar,
  localized tooltip + accessible name (en/de/tr, English fallback), keyboard-operable,
  stable `ValueKey` (`jet_print.preview.export`, `jet_print.preview.print`).
- The library invokes the callback and nothing else — busy UI, saving, sharing are host
  concerns (single awaitable export; hosts show indeterminate progress).

### B9 — Serialization untouched (FR-012)
No change to `ReportTemplate` JSON, `schemaVersion`, or any codec. Export is read-only
over the rendered IR.

## 3. Test groups pinned to this contract

| Group | Asserts | Contract |
|-------|---------|----------|
| `pdf_export_test` | page count, MediaBox points (A4/Letter/custom), text objects + embedded fonts present, search-target text extractable, image placement vs preview geometry | B1, B2 |
| `pdf_determinism_test` | two exports byte-identical (hash); golden `invoice.pdf` pin; repeat-export over a partially-viewed lazy report identical | B3, B1 |
| `pdf_painter_parity_test` | per-primitive semantics (baseline placement, align math, fit rects, fill-then-stroke order) mirror `CanvasPainter` | B2 |
| `png_export_test` | exact ×1/×2/×3 dimensions; page order; byte determinism; `RangeError` out-of-range; `ArgumentError` scale ≤ 0 | B4, B3 |
| `export_fallback_test` | empty dataset / unresolved image / failed expression → valid artifact, same fallback as preview goldens, diagnostics intact, 0 crashes | B5 |
| `export_performance_test` | 1,000-record dataset → complete PDF < 10 s (SC-005) | B1 |
| `jet_report_printer_test` | fake presenter receives PDF bytes + page size + job name; cancellation → false; unavailable → `PrintUnavailableException` | B6 |
| `jet_report_preview_test` (extended) | actions absent without callbacks (011 parity), present with; invoked on tap/keyboard; accessible names; l10n en/de/tr | B8 |
| `layer_boundaries_test` (extended) | export files Flutter-free except `page_rasterizer.dart`; only `src/print/` imports `printing`; public surface = §1 exactly | B7 |
| `rendered_invoice_example_test` (extended) | playground save + print flows wired through public API only (SC-008) | B1–B8 |
