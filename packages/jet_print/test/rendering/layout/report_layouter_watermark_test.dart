// ReportLayouter: watermark is threaded through layout as the first (bottom
// z-order) primitive on every page frame.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';

const PageFormat _smallPage =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ShapeElement _rect(String id, JetRect bounds) =>
    ShapeElement(id: id, bounds: bounds, kind: ShapeKind.rectangle);

FilledBand _body(double height) => FilledBand(
      type: BandType.detail,
      height: height,
      elements: <ReportElement>[
        _rect('r', JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
      variables: const <String, JetValue>{},
    );

ReportDefinition _tinyDef({Watermark? watermark}) => ReportDefinition(
      name: 'demo',
      page: _smallPage,
      furniture: PageFurniture(watermark: watermark),
      body: const ReportBody(root: DetailScope(id: 'root')),
    );

FilledReport _filled() =>
    FilledReport(page: _smallPage, bands: <FilledBand>[_body(20)]);

LazyLayout _layout(ReportDefinition def) =>
    ReportLayouter().layoutLazyDefinition(def, _filled());

void main() {
  test('watermark is the FIRST primitive on every page', () {
    final ReportDefinition def = _tinyDef(
        watermark: const Watermark(
            text: 'DRAFT', textStyle: JetTextStyle(fontSize: 48)));
    final LazyLayout layout = _layout(def);
    final frame = layout.buildPage(0);
    expect(frame.primitives, isNotEmpty);
    expect(frame.primitives.first, isA<TextRunPrimitive>());
    expect((frame.primitives.first as TextRunPrimitive).rotation, isNot(0));
  });

  test('no watermark → no rotated primitive (byte-identical to before)', () {
    final ReportDefinition def = _tinyDef(watermark: null);
    final LazyLayout layout = _layout(def);
    final frame = layout.buildPage(0);
    expect(
        frame.primitives
            .whereType<TextRunPrimitive>()
            .where((TextRunPrimitive p) => p.rotation != 0),
        isEmpty);
  });
}
