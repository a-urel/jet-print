// Create + Move semantics through the controller's public API (US1 / T035 /
// FR-001/002/004/008/010/025). The command classes are private; their behavior
// is contracted here via the controller a consumer actually uses.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _twoBandFixture() => const ReportDefinition(
      name: 'Fixture',
      page: PageFormat.a4Portrait, // content width ~538.58, see margins 28.35
      furniture: PageFurniture(
        pageHeader:
            Band(id: 'pageHeader', type: BandType.pageHeader, height: 60),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 200,
              elements: <ReportElement>[
                TextElement(
                  id: 'keep1',
                  bounds: JetRect(x: 5, y: 5, width: 40, height: 12),
                  text: 'keep',
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// The detail band's elements.
List<ReportElement> _detail(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<BandNode>().first.band.elements;

void main() {
  group('createElement', () {
    test('inserts a typed, default-sized element with a fresh id, selected',
        () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_twoBandFixture());
      c.createElement(DesignerToolType.barcode,
          bandId: 'detail', at: const JetOffset(20, 20));

      final List<ReportElement> els = _detail(c);
      expect(els.length, 2);
      expect(els.last, isA<BarcodeElement>());
      expect(c.selection.singleOrNull, els.last.id);
      // The pre-existing sibling is untouched (non-destructive, FR-025).
      expect(els.first.id, 'keep1');
      expect(
          els.first.bounds, const JetRect(x: 5, y: 5, width: 40, height: 12));
      c.dispose();
    });

    test('clamps a near-edge drop inside the band ∩ page content area', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_twoBandFixture());
      // Drop near the bottom-right corner of the detail band.
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(530, 195));
      final JetRect b = _detail(c).last.bounds;
      const double contentWidth = 595.28 - 28.35 * 2;
      expect(b.x + b.width, lessThanOrEqualTo(contentWidth + 0.001));
      expect(b.y + b.height, lessThanOrEqualTo(200 + 0.001));
      expect(b.x, greaterThanOrEqualTo(0));
      expect(b.y, greaterThanOrEqualTo(0));
      c.dispose();
    });

    test('an unknown band id is ignored', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_twoBandFixture());
      c.createElement(DesignerToolType.text,
          bandId: 'ghost', at: const JetOffset(10, 10));
      expect(_detail(c).length, 1); // unchanged
      expect(c.canUndo, isFalse);
      c.dispose();
    });
  });

  group('moveBy', () {
    test('moves the selection, clamped to its band, and is undoable', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_twoBandFixture());
      c.select('keep1');
      c.moveBy(const JetOffset(10, 7));
      JetRect b = _detail(c).first.bounds;
      expect(b.x, 15);
      expect(b.y, 12);
      expect(c.canUndo, isTrue);
      c.undo();
      b = _detail(c).first.bounds;
      expect(b.x, 5);
      expect(b.y, 5);
      c.dispose();
    });

    test('clamps a move that would leave the band', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_twoBandFixture());
      c.select('keep1');
      c.moveBy(const JetOffset(-100, -100)); // try to push off the top-left
      final JetRect b = _detail(c).first.bounds;
      expect(b.x, 0);
      expect(b.y, 0);
      c.dispose();
    });

    test('with no selection is a no-op (no history entry)', () {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_twoBandFixture());
      c.moveBy(const JetOffset(10, 10));
      expect(c.canUndo, isFalse);
      c.dispose();
    });
  });
}
