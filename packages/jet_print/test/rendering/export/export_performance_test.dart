// Export performance.
//
// The 011 1,000-record performance dataset exports to a COMPLETE PDF in under
// 10 seconds without memory exhaustion. Unlike the first-page render budget
// (advisory), export has a hard bound, so the
// wall-clock gate is binding here; completeness is verified structurally.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';

import 'support/export_fixtures.dart';
import 'support/pdf_inspector.dart';

void main() {
  test('1,000 records export to a complete PDF in under 10 seconds', () async {
    final RenderedReport report = performanceReport();
    expect(report.pageCount, greaterThan(10),
        reason: 'fixture sanity: 1,000 records paginate to many pages');

    final Stopwatch watch = Stopwatch()..start();
    final Uint8List bytes = await const JetReportExporter().toPdf(report);
    watch.stop();

    // ignore: avoid_print
    print('1,000 records -> ${report.pageCount} pages,'
        '${bytes.length} bytes in ${watch.elapsedMilliseconds} ms');
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));

    final PdfInspector pdf = PdfInspector(bytes);
    expect(pdf.pageCount, report.pageCount,
        reason: 'the artifact must be COMPLETE — every page materialized '
            ', not just the lazily viewed ones');
    expect(pdf.textOnPage(report.pageCount - 1), contains('record 999'),
        reason: 'the last record lands on the last page');
  });
}
