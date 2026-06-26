// Controller renameElement / renameBand unit tests (spec 017 / Task 5).
//
// Black-box: drives only the public controller surface. Mirrors the fixture
// construction pattern from rename_test.dart / band_lifecycle_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/controller/band_walker.dart';

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

const JetRect _r = JetRect(x: 0, y: 0, width: 10, height: 10);

ReportDefinition _defWith({String? elementName, String? bandName}) =>
    ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 100,
              name: bandName,
              elements: <ReportElement>[
                TextElement(
                  id: 't1',
                  bounds: _r,
                  text: 'hi',
                  name: elementName,
                ),
              ],
            )),
          ],
        ),
      ),
    );

ReportElement? _findElement(ReportDefinition def, String id) {
  for (final Band b in allBands(def)) {
    for (final ReportElement e in b.elements) {
      if (e.id == id) return e;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('renameElement', () {
    test('sets element name and is undoable', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWith());
      c.renameElement('t1', 'Greeting');
      expect(_findElement(c.definition, 't1')?.name, 'Greeting');
      c.undo();
      expect(_findElement(c.definition, 't1')?.name, isNull);
      c.dispose();
    });

    test('normalizes blank to null', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWith(elementName: 'Old'));
      c.renameElement('t1', '   ');
      expect(_findElement(c.definition, 't1')?.name, isNull);
      c.dispose();
    });

    test('renaming to the same value records no history', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWith());
      final bool before = c.canUndo; // false
      c.renameElement('t1', null); // already null — no change
      expect(c.canUndo, before);
      c.dispose();
    });

    test('notifies listeners exactly once on a real change', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWith());
      int notifications = 0;
      c.addListener(() => notifications++);
      c.renameElement('t1', 'Label');
      expect(notifications, 1);
      c.dispose();
    });
  });

  group('renameBand', () {
    test('sets band name', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWith());
      c.renameBand('detail', 'Lines');
      expect(findBand(c.definition, 'detail')?.name, 'Lines');
      c.dispose();
    });

    test('normalizes blank band name to null', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWith(bandName: 'Old'));
      c.renameBand('detail', '  ');
      expect(findBand(c.definition, 'detail')?.name, isNull);
      c.dispose();
    });

    test('renaming band to same value records no history', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _defWith(bandName: 'Lines'));
      final bool before = c.canUndo;
      c.renameBand('detail', 'Lines');
      expect(c.canUndo, before);
      c.dispose();
    });
  });
}
