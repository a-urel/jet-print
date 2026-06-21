// Web (CanvasKit) render + export smoke — runs ONLY in the browser so it
// exercises the real web rendering engine, not the VM. Asserts the three
// CanvasKit soft spots (E4 §5): canvas render, PNG export via toByteData,
// PDF export. No dart:io (must compile on web).
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _definition() => const ReportDefinition(
      name: 'Web smoke',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(
          id: 'body/title',
          type: BandType.title,
          height: 48,
          elements: <ReportElement>[
            TextElement(
              id: 'h',
              bounds: JetRect(x: 0, y: 0, width: 300, height: 24),
              text: 'WEB RENDER',
              style: JetTextStyle(fontSize: 18, weight: JetFontWeight.bold),
            ),
          ],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[]),
      ),
    );

RenderedReport _render() => const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF export produces valid bytes in the browser', () async {
    final Uint8List pdf = await const JetReportExporter().toPdf(_render());
    expect(pdf.length, greaterThan(100));
    // %PDF- magic header.
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  test('PNG export (toByteData on CanvasKit) produces a valid image',
      () async {
    final Uint8List png =
        await const JetReportExporter().pageToPng(_render(), 0);
    expect(png.length, greaterThan(100));
    // PNG 8-byte signature.
    expect(png.sublist(0, 8),
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  });
}
