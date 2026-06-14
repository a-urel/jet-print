// Letter / landscape page propagation golden (018 / US3 / contract C7.1; IV).
//
// Proves a non-default page (Letter, landscape, Narrow margins) reaches all
// three surfaces identically: the export rasterizer sizes the page to exactly
// round(792) x round(612) px (the size proof), and canvas + preview goldens pin
// its rendered appearance. Black-box: public API only (the default-A4 report
// goldens are untouched, so they stay byte-identical — C7.2).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

// Letter landscape (612 x 792 rotated) with Narrow (14.17) margins.
const PageFormat _letterLandscape = PageFormat(
  width: 792,
  height: 612,
  margins: JetEdgeInsets.all(14.17),
);

// The reified equivalent of the legacy title + master-detail report, authored
// directly with the SAME path-based ids the template→definition adapter assigns
// (title → body slot, the master-level detail band → a root BandNode), so all
// three surfaces stay byte-identical (spec 024).
ReportDefinition _definition() => const ReportDefinition(
      name: 'Letter Landscape',
      page: _letterLandscape,
      body: ReportBody(
        title: Band(
          id: 'body/title',
          type: BandType.title,
          height: 64,
          elements: <ReportElement>[
            TextElement(
              id: 'heading',
              bounds: JetRect(x: 0, y: 0, width: 360, height: 28),
              text: 'LANDSCAPE REPORT',
              style: JetTextStyle(fontSize: 22, weight: JetFontWeight.bold),
            ),
          ],
        ),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 40,
              elements: <ReportElement>[
                TextElement(
                  id: 'body',
                  bounds: JetRect(x: 0, y: 4, width: 420, height: 18),
                  text: 'Body content spanning the wide content area.',
                ),
              ],
            )),
          ],
        ),
      ),
    );

RenderedReport _rendered() => const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );

Future<ui.Image> _decode(Uint8List png) async {
  final ui.Codec codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export rasterizes the Letter/landscape page at its true size',
      () async {
    const JetReportExporter exporter = JetReportExporter();
    final Uint8List png = await exporter.pageToPng(_rendered(), 0);
    final ui.Image image = await _decode(png);
    // The export adopts the page exactly — the WYSIWYG size guarantee (C7.1).
    expect(image.width, 792);
    expect(image.height, 612);
  });

  testWidgets('the canvas renders the Letter/landscape page (golden)',
      (WidgetTester tester) async {
    await pumpDesignerWith(
      tester,
      controller: JetReportDesignerController(definition: _definition()),
      themeMode: ThemeMode.light,
      rulers: false,
      grid: false,
    );
    await expectLater(
      find.byType(JetReportDesigner),
      matchesGoldenFile('page_letter_landscape_canvas_light.png'),
    );
  });

  testWidgets('the exported page matches its golden',
      (WidgetTester tester) async {
    const JetReportExporter exporter = JetReportExporter();
    late final ui.Image image;
    // Real async (rasterize + decode) must run on the real clock.
    await tester.runAsync(() async {
      final Uint8List png = await exporter.pageToPng(_rendered(), 0);
      image = await _decode(png);
    });
    await expectLater(
      image,
      matchesGoldenFile('page_letter_landscape_export.png'),
    );
  });
}
