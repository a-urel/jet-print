import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/controller/commands/set_watermark_command.dart';
import 'package:jet_print/src/designer/controller/designer_document.dart';

ReportDefinition _def({Watermark? watermark}) => ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(watermark: watermark),
      body: const ReportBody(root: DetailScope(id: 'root')),
    );

DesignerDocument _doc({Watermark? watermark}) => DesignerDocument(
      definition: _def(watermark: watermark),
      selection: Selection.empty,
    );

void main() {
  group('SetWatermarkCommand', () {
    test('sets a watermark onto furniture', () {
      final DesignerDocument before = _doc();
      final DesignerDocument after =
          const SetWatermarkCommand(Watermark(text: 'DRAFT')).apply(before);
      expect(
          after.definition.furniture.watermark, const Watermark(text: 'DRAFT'));
    });

    test('clears the watermark (null) — copyWith cannot, so fresh furniture',
        () {
      final DesignerDocument before =
          _doc(watermark: const Watermark(text: 'X'));
      final DesignerDocument after =
          const SetWatermarkCommand(null).apply(before);
      expect(after.definition.furniture.watermark, isNull);
    });

    test('preserves other furniture slots when setting watermark', () {
      const header = Band(id: 'ph', type: BandType.pageHeader, height: 20);
      final DesignerDocument before = DesignerDocument(
        definition: ReportDefinition(
          name: 'r',
          page: PageFormat.a4Portrait,
          furniture: const PageFurniture(pageHeader: header),
          body: const ReportBody(root: DetailScope(id: 'root')),
        ),
        selection: Selection.empty,
      );
      final DesignerDocument after =
          const SetWatermarkCommand(Watermark(text: 'D')).apply(before);
      expect(after.definition.furniture.pageHeader, header);
      expect(after.definition.furniture.watermark, const Watermark(text: 'D'));
    });

    test('no-op when watermark already equals target', () {
      final DesignerDocument before =
          _doc(watermark: const Watermark(text: 'D'));
      final DesignerDocument after =
          const SetWatermarkCommand(Watermark(text: 'D')).apply(before);
      expect(identical(after, before), isTrue);
    });
  });

  group('controller.setWatermark', () {
    test('commits and is undoable', () {
      final c = JetReportDesignerController(definition: _def());
      c.setWatermark(const Watermark(text: 'DRAFT'));
      expect(c.definition.furniture.watermark, const Watermark(text: 'DRAFT'));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.definition.furniture.watermark, isNull);
      c.dispose();
    });
  });
}
