// Mobile render + export smoke. Runs in the VM with defaultTargetPlatform
// pinned to a mobile target, so it guards platform-CONDITIONAL Dart code on
// the export path (the class of bug E4's `_d()` number helper fixed). It does
// NOT exercise the real iOS/Android Impeller renderer — that is the manual
// sim/emulator smoke (E5 SC-002). No dart:io.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _definition() => const ReportDefinition(
      name: 'Mobile smoke',
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
              text: 'MOBILE RENDER 5.0',
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

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    group('$platform', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      test('PDF export produces valid bytes', () async {
        final Uint8List pdf = await const JetReportExporter().toPdf(_render());
        expect(pdf.length, greaterThan(100));
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      });

      test('PNG export (page rasterizer) produces a valid image', () async {
        final Uint8List png =
            await const JetReportExporter().pageToPng(_render(), 0);
        expect(png.length, greaterThan(100));
        expect(png.sublist(0, 8),
            <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      });
    });
  }
}
