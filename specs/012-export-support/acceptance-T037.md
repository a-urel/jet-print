# T037 — Acceptance record (export support, spec 012)

**Closed:** 2026-06-20, via Epic 1 (release hygiene), "automate + waive".

## Automated coverage (replaces the automatable quickstart steps)
- `JetReportExporter.toPdf` / `pageToPng`: `test/rendering/export/*` (byte
  determinism, page count/size, selectable text, scale math, range/scale errors).
- `JetReportPrinter` presenter seam: `test/print/jet_report_printer_test.dart`
  (same bytes as `toPdf`, true page size, job name, cancel→false, unavailable→
  `PrintUnavailableException`).
- Preview toolbar actions fire their callbacks and are hidden without them:
  `test/designer/preview/jet_report_preview_test.dart` group "export/print
  toolbar actions (012 — contract B8; FR-014/FR-015)" — 5 tests covering:
  absent when both callbacks null, export-only wiring, print-only wiring,
  both wired independently, and keyboard activation.

## Human-verified, then waived from per-release manual repetition
The following depend on OS-native dialogs the test harness cannot drive; verified
once by inspection in the macOS playground and waived going forward:
- Clicking the preview **export** action opens the native macOS save panel and
  writes a `.pdf` that opens in a standard (Quartz) viewer with extractable text.
- Clicking the preview **print** action opens the OS print dialog and
  print-to-file produces a document matching the preview page-for-page.

These remain re-verifiable by running `apps/jet_print_playground` and using the
preview toolbar; they are no longer a release blocker.
