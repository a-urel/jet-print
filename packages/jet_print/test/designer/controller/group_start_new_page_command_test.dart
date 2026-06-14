// Group startNewPage command via the controller (023). Public-API tests
// (no `src/`): the controller dispatches SetGroupStartNewPageCommand internally.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _grouped() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'invoice',
              name: 'invoice',
              key: r'$F{invoiceNo}',
              header: Band(id: 'gh', type: BandType.groupHeader, height: 20),
              footer: Band(id: 'gf', type: BandType.groupFooter, height: 20),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 20)),
          ],
        ),
      ),
    );

GroupLevel _groupById(JetReportDesignerController c, String id) =>
    c.definition.body.root.groups.firstWhere((GroupLevel g) => g.id == id);

void main() {
  test('sets a group to start on a new page, with undo/redo', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _grouped());
    addTearDown(c.dispose);

    expect(_groupById(c, 'invoice').startNewPage, isFalse);
    c.setGroupStartNewPage('invoice', true);
    expect(_groupById(c, 'invoice').startNewPage, isTrue);
    c.undo();
    expect(_groupById(c, 'invoice').startNewPage, isFalse);
    c.redo();
    expect(_groupById(c, 'invoice').startNewPage, isTrue);
  });

  test("preserves the group's other fields", () {
    final JetReportDesignerController c = JetReportDesignerController(
      definition: const ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            groups: <GroupLevel>[
              GroupLevel(
                id: 'g',
                name: 'g',
                key: r'$F{k}',
                keepTogether: true,
                reprintHeaderOnEachPage: true,
                header: Band(id: 'gh', type: BandType.groupHeader, height: 10),
              ),
            ],
            children: <ScopeNode>[
              BandNode(Band(id: 'detail', type: BandType.detail, height: 10)),
            ],
          ),
        ),
      ),
    );
    addTearDown(c.dispose);

    c.setGroupStartNewPage('g', true);
    final GroupLevel g = _groupById(c, 'g');
    expect(g.startNewPage, isTrue);
    expect(g.keepTogether, isTrue);
    expect(g.reprintHeaderOnEachPage, isTrue);
    expect(g.key, r'$F{k}');
  });

  test('an unchanged value or unknown group pushes no history (no-op)', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _grouped());
    addTearDown(c.dispose);

    c.setGroupStartNewPage('invoice', false); // already false → no-op
    c.setGroupStartNewPage('ghost', true); // unknown group → no-op
    expect(c.canUndo, isFalse);
  });
}
