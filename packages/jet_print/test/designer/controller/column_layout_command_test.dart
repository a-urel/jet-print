// Column-layout set/remove commands + controller methods (spec 035 / Task 1).
// Public-API controller tests (no `src/` imports), mirroring
// band_collection_command_test.dart and controller_history_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A pure single-detail body: one root scope, one detail BandNode with one
/// element, no groups/footer/title/summary/noData — the eligible label shape.
ReportDefinition _pureSingleDetail() => const ReportDefinition(
      name: 'labels',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                TextElement(
                  id: 't',
                  bounds: JetRect(x: 0, y: 0, width: 100, height: 20),
                  text: 'x',
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// The sole detail band, read through the public scope tree.
Band _detail(JetReportDesignerController c) =>
    (c.definition.body.root.children.single as BandNode).band;

void main() {
  test('setColumnLayout sets the layout as one undoable step', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _pureSingleDetail());
    addTearDown(c.dispose);
    const ColumnLayout layout = ColumnLayout(
        columnCount: 2, columnWidth: 200, columnSpacing: 8, rowSpacing: 4);

    c.setColumnLayout('detail', layout);
    expect(_detail(c).columnLayout, layout);

    c.undo();
    expect(_detail(c).columnLayout, isNull);
    c.redo();
    expect(_detail(c).columnLayout, layout);
  });

  test(
      'removeColumnLayout clears the layout, preserving id/type/height/elements',
      () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _pureSingleDetail());
    addTearDown(c.dispose);
    c.setColumnLayout(
        'detail',
        const ColumnLayout(
            columnCount: 3, columnWidth: 120, columnSpacing: 0, rowSpacing: 0));

    c.removeColumnLayout('detail');

    final Band b = _detail(c);
    expect(b.columnLayout, isNull);
    expect(b.id, 'detail');
    expect(b.type, BandType.detail);
    expect(b.height, 80);
    expect(b.elements.map((ReportElement e) => e.id), <String>['t']);
  });

  test('setColumnLayout is a no-op for an unknown band id', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _pureSingleDetail());
    addTearDown(c.dispose);

    c.setColumnLayout(
        'nope',
        const ColumnLayout(
            columnCount: 2, columnWidth: 200, columnSpacing: 0, rowSpacing: 0));

    expect(_detail(c).columnLayout, isNull);
    expect(c.canUndo, isFalse);
  });

  test('removeColumnLayout is a no-op when the band has no layout', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _pureSingleDetail());
    addTearDown(c.dispose);

    c.removeColumnLayout('detail');

    expect(c.canUndo, isFalse);
  });

  // Regression: RemoveColumnLayoutCommand rebuilt Band via direct constructor
  // and silently dropped `visible` (spec-visible-property bug).
  test('removeColumnLayout preserves visible=false while clearing columnLayout',
      () {
    // Build a definition with a non-default visible on the detail band.
    final ReportDefinition base = ReportDefinition(
      name: 'labels',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 80,
              visible: const BoolProperty(value: false),
              elements: const <ReportElement>[
                TextElement(
                  id: 't',
                  bounds: JetRect(x: 0, y: 0, width: 100, height: 20),
                  text: 'x',
                ),
              ],
            )),
          ],
        ),
      ),
    );

    final JetReportDesignerController c =
        JetReportDesignerController(definition: base);
    addTearDown(c.dispose);

    c.setColumnLayout(
      'detail',
      const ColumnLayout(
          columnCount: 2, columnWidth: 200, columnSpacing: 8, rowSpacing: 4),
    );
    c.removeColumnLayout('detail');

    final Band b = _detail(c);
    expect(b.columnLayout, isNull,
        reason: 'columnLayout must be cleared by the command');
    expect(b.visible, const BoolProperty(value: false),
        reason: 'visible must survive removeColumnLayout');
  });
}
