// Numeric geometry + text editing through the controller (US5 / T066 / FR-019).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportTemplate _fixture() => const ReportTemplate(
      name: 'F',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 300,
          elements: <ReportElement>[
            TextElement(
                id: 't1',
                bounds: JetRect(x: 10, y: 10, width: 40, height: 20),
                text: 'hello'),
            ShapeElement(
                id: 's1',
                bounds: JetRect(x: 10, y: 50, width: 40, height: 20),
                kind: ShapeKind.rectangle),
          ],
        ),
      ],
    );

JetRect _b(JetReportDesignerController c, String id) =>
    c.template.bands.first.elements
        .firstWhere((ReportElement e) => e.id == id)
        .bounds;

JetReportDesignerController _open() =>
    JetReportDesignerController()..open(_fixture());

void main() {
  group('setGeometry', () {
    test('sets individual fields, leaving the others, and is undoable', () {
      final JetReportDesignerController c = _open();
      c.setGeometry('t1', x: 25, width: 80);
      expect(_b(c, 't1'), const JetRect(x: 25, y: 10, width: 80, height: 20));
      c.undo();
      expect(_b(c, 't1'), const JetRect(x: 10, y: 10, width: 40, height: 20));
      c.dispose();
    });

    test('clamps to the band ∩ page content area', () {
      final JetReportDesignerController c = _open();
      c.setGeometry('t1', x: 100000);
      const double contentWidth = 595.28 - 28.35 * 2;
      expect(_b(c, 't1').x + _b(c, 't1').width,
          lessThanOrEqualTo(contentWidth + 0.001));
      c.dispose();
    });

    test('a no-op set records no history', () {
      final JetReportDesignerController c = _open();
      c.setGeometry('t1', x: 10); // already 10
      expect(c.canUndo, isFalse);
      c.dispose();
    });
  });

  group('setText', () {
    test('sets a text element and is undoable', () {
      final JetReportDesignerController c = _open();
      c.setText('t1', 'world');
      expect(
          (c.template.bands.first.elements.first as TextElement).text, 'world');
      c.undo();
      expect(
          (c.template.bands.first.elements.first as TextElement).text, 'hello');
      c.dispose();
    });

    test('is a no-op for a non-text element (no history)', () {
      final JetReportDesignerController c = _open();
      c.setText('s1', 'nope');
      expect(c.canUndo, isFalse);
      c.dispose();
    });

    test('setting the same text records no history', () {
      final JetReportDesignerController c = _open();
      c.setText('t1', 'hello');
      expect(c.canUndo, isFalse);
      c.dispose();
    });
  });
}
