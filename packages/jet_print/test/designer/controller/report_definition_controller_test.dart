// Phase 4 / T024 (spec 024): the designer controller authors a
// `ReportDefinition` directly — groups and scopes are first-class, selectable,
// addressable entities, and create/delete/edit of a group or scope is a single
// undoable step. Consumer-style: through `package:jet_print/jet_print.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A minimal definition: the master root scope with one detail band.
ReportDefinition _flat() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 100)),
          ],
        ),
      ),
    );

/// A definition whose root scope owns one group with a header + footer band.
ReportDefinition _grouped() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'g1',
              name: 'category',
              key: r'$F{category}',
              header: Band(id: 'gh', type: BandType.groupHeader, height: 24),
              footer: Band(id: 'gf', type: BandType.groupFooter, height: 24),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 100)),
          ],
        ),
      ),
    );

void main() {
  group('controller authors a ReportDefinition (T024)', () {
    test('holds the definition it is constructed with', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _flat());
      expect(c.definition.body.root.id, 'root');
      c.dispose();
    });

    test('defaults to a blank furniture+detail definition when none given', () {
      final JetReportDesignerController c = JetReportDesignerController();
      expect(c.definition.furniture.pageHeader, isNotNull);
      expect(c.definition.furniture.pageFooter, isNotNull);
      expect(c.definition.body.root.children, hasLength(1));
      c.dispose();
    });

    test('a band is selectable by its stable id', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _flat());
      c.selectBand('detail');
      expect(c.selection.bandId, 'detail');
      expect(c.selection.groupId, isNull);
      expect(c.selection.scopeId, isNull);
      expect(c.selection.isReport, isFalse);
      c.dispose();
    });

    test('a group is selectable by its stable id', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _grouped());
      c.selectGroup('g1');
      expect(c.selection.groupId, 'g1');
      expect(c.selection.bandId, isNull);
      expect(c.selection.scopeId, isNull);
      expect(c.selection.ids, isEmpty);
      c.dispose();
    });

    test('a scope is selectable by its stable id', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _flat());
      c.selectScope('root');
      expect(c.selection.scopeId, 'root');
      expect(c.selection.groupId, isNull);
      c.dispose();
    });
  });

  group('group lifecycle is undoable (T024 / FR-015)', () {
    test('createGroup appends a level to the scope and undoes', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _flat());
      c.createGroup('root', name: 'category', key: r'$F{category}');
      expect(c.definition.body.root.groups, hasLength(1));
      expect(c.definition.body.root.groups.single.name, 'category');
      expect(c.definition.body.root.groups.single.key, r'$F{category}');
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.definition.body.root.groups, isEmpty);
      c.dispose();
    });

    test('deleteGroup removes the level and undoes', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _grouped());
      c.deleteGroup('g1');
      expect(c.definition.body.root.groups, isEmpty);
      c.undo();
      expect(c.definition.body.root.groups, hasLength(1));
      c.dispose();
    });

    test('setGroupKey changes only the key, undoably', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _grouped());
      c.setGroupKey('g1', r'$F{region}');
      expect(c.definition.body.root.groups.single.key, r'$F{region}');
      c.undo();
      expect(c.definition.body.root.groups.single.key, r'$F{category}');
      c.dispose();
    });

    test('each group flag toggles as one undoable step', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _grouped());
      c.setGroupStartNewPage('g1', true);
      c.setGroupKeepTogether('g1', true);
      c.setGroupReprintHeader('g1', true);
      final GroupLevel g = c.definition.body.root.groups.single;
      expect(g.startNewPage, isTrue);
      expect(g.keepTogether, isTrue);
      expect(g.reprintHeaderOnEachPage, isTrue);
      c.undo(); // reverts only the reprint flag (last edit)
      expect(c.definition.body.root.groups.single.reprintHeaderOnEachPage,
          isFalse);
      expect(c.definition.body.root.groups.single.keepTogether, isTrue);
      c.dispose();
    });
  });

  group('scope lifecycle is undoable (T024 / FR-015)', () {
    test('createScope adds a nested scope child and undoes', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _flat());
      c.createScope('root', collectionField: 'lines');
      final Iterable<NestedScope> nested =
          c.definition.body.root.children.whereType<NestedScope>();
      expect(nested, hasLength(1));
      expect(nested.single.scope.collectionField, 'lines');
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.definition.body.root.children.whereType<NestedScope>(), isEmpty);
      c.dispose();
    });

    test('deleteScope removes a nested scope and undoes', () {
      final JetReportDesignerController c =
          JetReportDesignerController(definition: _flat());
      c.createScope('root', collectionField: 'lines');
      final String scopeId = c.definition.body.root.children
          .whereType<NestedScope>()
          .single
          .scope
          .id;
      c.deleteScope(scopeId);
      expect(c.definition.body.root.children.whereType<NestedScope>(), isEmpty);
      c.undo();
      expect(c.definition.body.root.children.whereType<NestedScope>(),
          hasLength(1));
      c.dispose();
    });
  });
}
