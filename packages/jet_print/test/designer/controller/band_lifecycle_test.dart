// Phase 5 / T034 (spec 024 / US3 / C10): band lifecycle through the controller —
// add / remove / reorder / retype a band, each a single undoable step, with
// stable ids across reorder and retype (FR-002, FR-012, FR-015). Consumer-style:
// public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// Furniture page header + a master scope with one group (no bands yet) and two
/// detail bands.
ReportDefinition _seed() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(id: 'ph', type: BandType.pageHeader, height: 24),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(id: 'g1', name: 'g', key: r'$F{k}'),
          ],
          children: <ScopeNode>[
            BandNode(Band(id: 'd1', type: BandType.detail, height: 80)),
            BandNode(Band(id: 'd2', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );

List<String> _detailIds(JetReportDesignerController c) => <String>[
      for (final ScopeNode n in c.definition.body.root.children)
        if (n is BandNode) n.band.id,
    ];

void main() {
  group('add band (T034)', () {
    test('addBand fills an empty singleton slot, selects it, undoably', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.addBand(BandType.title);
      final Band? title = c.definition.body.title;
      expect(title, isNotNull);
      expect(title!.type, BandType.title);
      expect(c.selection.bandId, title.id);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.definition.body.title, isNull);
      c.dispose();
    });

    test('addBand on an occupied singleton slot is a no-op (no history)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.addBand(BandType.pageHeader); // slot already holds 'ph'
      expect(c.definition.furniture.pageHeader!.id, 'ph');
      expect(c.canUndo, isFalse);
      c.dispose();
    });

    test('addDetailBand appends a per-row band to a scope, undoably', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.addDetailBand('root');
      expect(_detailIds(c), hasLength(3));
      expect(c.selection.bandId, _detailIds(c).last);
      c.undo();
      expect(_detailIds(c), <String>['d1', 'd2']);
      c.dispose();
    });

    test('addGroupBand fills a group header/footer slot, undoably', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.addGroupBand('g1', header: true);
      final GroupLevel g = c.definition.body.root.groups.single;
      expect(g.header, isNotNull);
      expect(g.header!.type, BandType.groupHeader);
      c.addGroupBand('g1', header: false);
      expect(c.definition.body.root.groups.single.footer?.type,
          BandType.groupFooter);
      c.undo(); // removes the footer
      expect(c.definition.body.root.groups.single.footer, isNull);
      expect(c.definition.body.root.groups.single.header, isNotNull);
      c.dispose();
    });
  });

  group('remove band (T034)', () {
    test('removeBand drops a scope per-row band, undoably', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.removeBand('d1');
      expect(_detailIds(c), <String>['d2']);
      c.undo();
      expect(_detailIds(c), <String>['d1', 'd2']);
      c.dispose();
    });

    test('removeBand clears a furniture slot, undoably', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.removeBand('ph');
      expect(c.definition.furniture.pageHeader, isNull);
      c.undo();
      expect(c.definition.furniture.pageHeader?.id, 'ph');
      c.dispose();
    });
  });

  group('reorder band (T034 / C10 — ids stable)', () {
    test('moveBand reorders within the scope, preserving ids, undoably', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.moveBand('d2', -1); // move the second detail band up
      expect(_detailIds(c), <String>['d2', 'd1'],
          reason: 'order changes but ids are unchanged');
      c.undo();
      expect(_detailIds(c), <String>['d1', 'd2']);
      c.dispose();
    });

    test('moveBand past the end clamps (no-op, no history)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.moveBand('d2', 1); // already last
      expect(_detailIds(c), <String>['d1', 'd2']);
      expect(c.canUndo, isFalse);
      c.dispose();
    });
  });

  group('retype band (T034 / FR-012 — moves to the matching slot)', () {
    test(
        'retypeBand relocates a band to the slot for the new type, keeping its '
        'id, undoably', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      c.retypeBand('d1', BandType.title);
      // The band left the scope and became the body title — same id, new type.
      expect(_detailIds(c), <String>['d2']);
      expect(c.definition.body.title?.id, 'd1');
      expect(c.definition.body.title?.type, BandType.title);
      expect(c.selection.bandId, 'd1');
      c.undo();
      expect(c.definition.body.title, isNull);
      expect(_detailIds(c), <String>['d1', 'd2']);
      c.dispose();
    });

    test('retypeBand into an occupied slot is a no-op (no history)', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _seed());
      // pageHeader is occupied by 'ph', so retyping d1 → pageHeader is rejected.
      c.retypeBand('d1', BandType.pageHeader);
      expect(_detailIds(c), <String>['d1', 'd2']);
      expect(c.definition.furniture.pageHeader!.id, 'ph');
      expect(c.canUndo, isFalse);
      c.dispose();
    });
  });
}
