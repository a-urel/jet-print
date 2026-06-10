// PDF byte-determinism (012 — contract B3; FR-007/FR-011, SC-004; T004/T014).
//
// Identical rendered inputs + options -> byte-identical artifacts. All
// normally-varying PDF metadata (creation timestamp, document ID) is
// fixed/zeroed; no clock, randomness, or ambient-locale read exists anywhere
// in the export path. The golden invoice.pdf is a deliberate-update pin:
// bytes may legitimately shift across Dart SDK / dart_pdf upgrades (zlib) —
// regenerate with `--update-goldens` and review the diff (research.md §2).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';

import '../../support/workspace.dart';
import 'support/export_fixtures.dart';

void main() {
  const JetReportExporter exporter = JetReportExporter();

  test('exporting the identical rendered input twice is byte-identical',
      () async {
    final Uint8List first = await exporter.toPdf(invoiceReport());
    final Uint8List second = await exporter.toPdf(invoiceReport());
    expect(second, first,
        reason: 'two renders of identical inputs must export to identical '
            'bytes (FR-007) — a timestamp, random ID, or unstable ordering '
            'has leaked into the artifact');
  });

  test('re-exporting the same RenderedReport instance is byte-identical',
      () async {
    final RenderedReport report = invoiceReport();
    final Uint8List first = await exporter.toPdf(report);
    final Uint8List second = await exporter.toPdf(report);
    expect(second, first,
        reason: 'repeat export over the cached frames must be stable');
  });

  test('a partially viewed lazy report exports identically (FR-011)', () async {
    final Uint8List fresh = await exporter.toPdf(invoiceReport());
    final RenderedReport viewed = invoiceReport();
    viewed.pageAt(1); // the preview looked at page 2 first
    final Uint8List afterViewing = await exporter.toPdf(viewed);
    expect(afterViewing, fresh,
        reason: 'what the preview has lazily materialized is irrelevant: '
            'export materializes all pages in order');
  });

  test('matches the pinned golden invoice.pdf (deliberate-update artifact)',
      () async {
    final File golden = File(
        '${findWorkspaceRoot().path}/packages/jet_print/test/goldens/invoice.pdf');
    final Uint8List bytes = await exporter.toPdf(invoiceReport());
    if (autoUpdateGoldenFiles) {
      golden.writeAsBytesSync(bytes);
      return;
    }
    expect(golden.existsSync(), isTrue,
        reason: 'missing golden pin — generate it once with '
            '`flutter test --update-goldens` and commit it (T014)');
    expect(bytes, golden.readAsBytesSync(),
        reason: 'the exported invoice changed. If deliberate (SDK/dart_pdf '
            'upgrade or a real visual change), regenerate with '
            '--update-goldens and review; otherwise determinism broke');
  });
}
