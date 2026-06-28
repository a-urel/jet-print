// SetWatermarkCommand tests, exercised through the public controller surface.
//
// Black-box: drives only JetReportDesignerController.setWatermark() and
// asserts via controller.definition.furniture.watermark. The command class and
// DesignerDocument are implementation details. Tests cover:
//   - set a watermark
//   - clear the watermark (null → fresh PageFurniture path)
//   - preserve other furniture slots (the silent-drop trap)
//   - no-op when the watermark already equals the target (canUndo stays false)
//   - round-trip + undo
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _def({Watermark? watermark, Band? pageHeader}) =>
    ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(watermark: watermark, pageHeader: pageHeader),
      body: const ReportBody(root: DetailScope(id: 'root')),
    );

JetReportDesignerController _controller(
        {Watermark? watermark, Band? pageHeader}) =>
    JetReportDesignerController(
      definition: _def(watermark: watermark, pageHeader: pageHeader),
    );

void main() {
  group('setWatermark — sets / clears watermark', () {
    test('set — stores the watermark on furniture', () {
      final c = _controller();
      c.setWatermark(const Watermark(text: 'DRAFT'));
      expect(c.definition.furniture.watermark, const Watermark(text: 'DRAFT'));
      c.dispose();
    });

    test('clear — null removes the watermark (fresh-furniture path)', () {
      final c = _controller(watermark: const Watermark(text: 'X'));
      c.setWatermark(null);
      expect(c.definition.furniture.watermark, isNull);
      c.dispose();
    });
  });

  group('setWatermark — preserves other furniture slots', () {
    test('pageHeader is untouched after setting watermark', () {
      const header = Band(id: 'ph', type: BandType.pageHeader, height: 20);
      final c = _controller(pageHeader: header);
      c.setWatermark(const Watermark(text: 'D'));
      expect(c.definition.furniture.pageHeader, header);
      expect(c.definition.furniture.watermark, const Watermark(text: 'D'));
      c.dispose();
    });
  });

  group('setWatermark — no-op when value unchanged', () {
    test('canUndo is false after setting the already-current watermark', () {
      final c = _controller(watermark: const Watermark(text: 'D'));
      c.setWatermark(const Watermark(text: 'D'));
      expect(c.canUndo, isFalse);
      c.dispose();
    });
  });

  group('setWatermark — undoable', () {
    test('undo restores the prior watermark', () {
      final c = _controller();
      c.setWatermark(const Watermark(text: 'DRAFT'));
      expect(c.definition.furniture.watermark, const Watermark(text: 'DRAFT'));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.definition.furniture.watermark, isNull);
      c.dispose();
    });
  });
}
