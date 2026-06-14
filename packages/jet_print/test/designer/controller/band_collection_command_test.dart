// Scope collection-binding command + scope addressing (US3 / FR-015,
// FR-015a). In the reified model (spec 024) the collection a region iterates is
// a property of its *scope*, not of a band: a nested master/detail is a
// `NestedScope` under the root scope. Public-API controller tests (no `src/`).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// The root master scope with one per-row band and one nested child scope —
/// the reified shape of the old "detail band carrying a child detail band".
ReportDefinition _nested() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 100)),
            NestedScope(DetailScope(
              id: 'sub',
              children: <ScopeNode>[
                BandNode(
                    Band(id: 'subDetail', type: BandType.detail, height: 40)),
              ],
            )),
          ],
        ),
      ),
    );

DetailScope _sub(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<NestedScope>().single.scope;

void main() {
  test('designates a scope as collection-bound, with undo/redo', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _nested());
    addTearDown(c.dispose);

    c.setScopeCollection('sub', 'lines');
    expect(_sub(c).collectionField, 'lines');
    c.undo();
    expect(_sub(c).collectionField, isNull);
    c.redo();
    expect(_sub(c).collectionField, 'lines');
  });

  test('addresses a nested scope by id, leaving the parent untouched', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _nested());
    addTearDown(c.dispose);

    c.setScopeCollection('sub', 'subLines');
    expect(_sub(c).collectionField, 'subLines');
    // The root master scope stays collection-blind.
    expect(c.definition.body.root.collectionField, isNull);
  });

  test('clearing reverts to master scope; a no-op pushes no history', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _nested());
    addTearDown(c.dispose);

    c.setScopeCollection('sub', 'lines');
    c.setScopeCollection('sub', 'lines'); // no-op (unchanged)
    c.setScopeCollection('sub', null); // clear
    expect(_sub(c).collectionField, isNull);

    c.undo(); // undo the clear → 'lines'
    expect(_sub(c).collectionField, 'lines');
    c.undo(); // undo the set → null (the no-op added no entry)
    expect(_sub(c).collectionField, isNull);
  });
}
