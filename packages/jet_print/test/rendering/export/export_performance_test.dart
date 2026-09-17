// Export scaling.
//
// The 011 performance dataset exports to a COMPLETE PDF whose cost grows
// LINEARLY with the row count. Completeness and scale are both verified
// structurally; neither reads a clock.
//
// This test used to assert `watch.elapsed < Duration(seconds: 10)`, and its
// header called that bound binding rather than advisory. Two measurements
// retired it. First, the export it guards actually takes ~40ms, so the ceiling
// carried roughly 250x headroom: it could not detect a 2x, a 10x, or even a 50x
// regression, only a hang — and `package:test`'s default 30s per-test timeout
// already catches a hang, sooner and without an assertion whose truth depends on
// the host. Second, a sibling designer test with a far tighter ceiling did fail
// on unmodified code purely from machine load, which is the failure mode any
// wall-clock assertion eventually has.
//
// Dropping it does retire a stated product commitment, deliberately. A 10-second
// bound checked on a shared CI runner never verified that commitment; it only
// ever failed when something was already very wrong. What replaces it is a
// claim the same code can actually keep: the work grows in proportion to the
// data.
//
// What this does NOT guard: cost inside the PDF WRITER. The primitive count is
// the ENGINE's output — a writer that re-emits content it already wrote produces
// identical frames. A writer that emits extra PAGES is caught, by the
// completeness assertion below. A writer that fattens each page is not, and
// deliberately so: an artifact-size guard was written for exactly that case and
// then failed its own teeth check. Emitting every text run twice grows the PDF
// by only ~21% (23.57 -> 28.56 bytes per record), because stream compression
// squashes the duplication — and it grows both dataset sizes alike, so a size
// RATIO cancels it entirely. Catching that needs a bound tighter than 21% on an
// absolute byte count, which could not survive the per-OS differences in font
// subsetting that already confine the goldens to macOS. A guard that cannot be
// watched failing does not earn its place, so there isn't one.
//
// Note what is NOT asserted: a timing ratio across two dataset sizes — the
// load-cancelling trick `test/designer/perf/large_design_drag_test.dart` uses —
// does not work here. At ~40ms the measurement is dominated by JIT warmup:
// whichever size runs first is the slower one regardless of size, so the ratio
// is noise and frequently inverted. Counting survives that; timing does not.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';

import 'support/export_fixtures.dart';
import 'support/pdf_inspector.dart';

/// The two dataset sizes. The larger is exactly twice the smaller, so linear
/// cost predicts exactly twice the emitted work.
const int _smallRun = 500;
const int _largeRun = 1000;

/// Each fixture row contributes one detail band carrying two text elements, so
/// the frames must hold exactly two primitives per row. This is the per-row
/// element count of `performanceReport`'s definition, not a magic number.
const int _primitivesPerRecord = 2;

void main() {
  test('1,000 records export to a complete PDF', () async {
    final RenderedReport report = performanceReport(records: _largeRun);
    expect(report.pageCount, greaterThan(10),
        reason: 'fixture sanity: $_largeRun records paginate to many pages');

    final Uint8List bytes = await const JetReportExporter().toPdf(report);

    final PdfInspector pdf = PdfInspector(bytes);
    expect(pdf.pageCount, report.pageCount,
        reason: 'the artifact must be COMPLETE — every page materialized '
            ', not just the lazily viewed ones');
    expect(pdf.textOnPage(report.pageCount - 1),
        contains('record ${_largeRun - 1}'),
        reason: 'the last record lands on the last page');
  });

  test('export work grows linearly with the row count', () async {
    final ({int pages, int primitives}) small = await _exportCost(_smallRun);
    final ({int pages, int primitives}) large = await _exportCost(_largeRun);

    // The primitive count is what `toPdf` walks: one `paintFrame` per page, and
    // every primitive in that page's frame painted into the PDF.
    //
    // The two assertions below do different jobs, and both are needed. The
    // absolute anchor catches a CONSTANT-FACTOR regression — emit a duplicate
    // per element and every size inflates alike, which a ratio cancels out
    // (verified: that injection leaves the ratio at exactly 2.0 and is caught
    // only by the anchor). The ratio catches SUPER-LINEAR growth, which the
    // anchor alone would read as a merely larger constant.
    expect(small.primitives, _smallRun * _primitivesPerRecord,
        reason: 'each row contributes exactly $_primitivesPerRecord '
            'primitives; a different total means the fixture changed and the '
            'rest of this test is measuring something else');
    expect(large.primitives, small.primitives * 2,
        reason: 'twice the rows must emit exactly twice the primitives '
            '(${small.primitives} -> ${large.primitives})');

    // Pagination is derived from the same rows, so page count scales with them
    // too. Held to a tolerance rather than an exact double: where a page
    // boundary falls is a layout decision this test has no business pinning.
    final double pageScaling = large.pages / small.pages;
    expect(pageScaling, closeTo(2.0, 0.1),
        reason: 'twice the rows must paginate to about twice the pages '
            '(${small.pages} -> ${large.pages})');
  });
}

/// Exports [records] rows and reports the work that export performed: the pages
/// it materialized and the primitives it painted.
///
/// Both come from the frames `toPdf` itself walks, and both are deterministic —
/// identical run to run, on any machine, under any load.
Future<({int pages, int primitives})> _exportCost(int records) async {
  final RenderedReport report = performanceReport(records: records);
  int primitives = 0;
  for (int i = 0; i < report.pageCount; i++) {
    primitives += report.pageAt(i).frame.primitives.length;
  }
  // Export for real: the counts above describe work that actually happened,
  // not work a hypothetical export would have done.
  final Uint8List bytes = await const JetReportExporter().toPdf(report);
  expect(PdfInspector(bytes).pageCount, report.pageCount,
      reason: 'the $records-row export must materialize every page');
  return (pages: report.pageCount, primitives: primitives);
}
