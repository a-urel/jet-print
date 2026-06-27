// Shape-forms WYSIWYG goldens (020 / US3 / C7.2–C7.3, SC-003).
//
// A page containing each new closed form (ellipse, triangle, diamond, pentagon,
// hexagon, star) — filled and stroked — must render identically on the design
// canvas and in PDF/PNG export, because both replay the SAME PathPrimitive from
// the one `shapePath`. Preview shares the export's RenderedReport + painter, so
// the export golden covers it too. The pre-existing line/rectangle report
// goldens are untouched, so they stay byte-identical (C7.3). Black-box: public
// API only.
@Tags(['golden'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

// A compact page holding the thirteen new forms in a row, each filled + stroked
// so both the fill and the stroke of the shared PathPrimitive are exercised.
const PageFormat _page = PageFormat(
  width: 952,
  height: 96,
  margins: JetEdgeInsets.all(8),
);

const JetBoxStyle _style = JetBoxStyle(
  fill: JetColor(0xFF7CB3F0),
  stroke: JetColor.black,
  strokeWidth: 2,
);

ShapeElement _form(String id, ShapeKind kind, double x) => ShapeElement(
      id: id,
      bounds: JetRect(x: x, y: 8, width: 64, height: 64),
      kind: kind,
      style: _style,
    );

// The reified equivalent of the legacy single detail-band report, authored
// directly with the SAME path-based id the template→definition adapter assigns
// (a master-level detail band → a root BandNode 'root/c0'), so the canvas and
// the export stay byte-identical (spec 024).
ReportDefinition _definition() => ReportDefinition(
      name: 'Shape Forms',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                _form('ellipse', ShapeKind.ellipse, 0),
                _form('triangle', ShapeKind.triangle, 72),
                _form('diamond', ShapeKind.diamond, 144),
                _form('pentagon', ShapeKind.pentagon, 216),
                _form('hexagon', ShapeKind.hexagon, 288),
                _form('star', ShapeKind.star, 360),
                _form('arrowRight', ShapeKind.arrowRight, 432),
                _form('arrowLeft', ShapeKind.arrowLeft, 504),
                _form('arrowUp', ShapeKind.arrowUp, 576),
                _form('arrowDown', ShapeKind.arrowDown, 648),
                _form('arrowDouble', ShapeKind.arrowDouble, 720),
                _form('chevron', ShapeKind.chevron, 792),
                _form('roundRect', ShapeKind.roundRect, 864),
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

  testWidgets('the canvas renders every new form (golden)',
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
      matchesGoldenFile('shape_forms_canvas_light.png'),
    );
  });

  testWidgets('the exported page matches the canvas form-for-form (golden)',
      (WidgetTester tester) async {
    const JetReportExporter exporter = JetReportExporter();
    late final ui.Image image;
    await tester.runAsync(() async {
      final Uint8List png = await exporter.pageToPng(_rendered(), 0);
      image = await _decode(png);
    });
    await expectLater(
      image,
      matchesGoldenFile('shape_forms_export.png'),
    );
  });
}
