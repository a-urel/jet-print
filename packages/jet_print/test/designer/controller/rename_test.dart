// Controller rename() unit tests (017 / US2 / C4).
//
// Black-box: drives only the public controller + serialization surface. rename()
// is the single undoable mutator behind the unified toolbar's inline rename; it
// must behave exactly like every other edit — one history entry, one
// notification, identity no-op on the same name — and leave serialization
// untouched (empty names stored verbatim; schemaVersion unchanged).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _named(String name) => ReportDefinition(
      name: name,
      page: PageFormat.a4Portrait,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 100,
              elements: <ReportElement>[
                TextElement(
                  id: 'e1',
                  bounds: JetRect(x: 0, y: 0, width: 40, height: 12),
                  text: 'x',
                ),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  test('rename(x) sets the definition name (C4.1)', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _named('Alpha'));
    c.rename('Beta');
    expect(c.definition.name, 'Beta');
    c.dispose();
  });

  test('rename is a single undoable step restoring the prior name (C4.2)', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _named('Alpha'));
    c.rename('Beta');
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.definition.name, 'Alpha');
    expect(c.canUndo, isFalse,
        reason: 'one rename = exactly one history entry');
    c.dispose();
  });

  test('rename restores the prior selection on undo (snapshot coherence)', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _named('Alpha'));
    c.select('e1');
    final Selection before = c.selection;
    c.rename('Beta');
    c.undo();
    expect(c.selection, before);
    c.dispose();
  });

  test('rename notifies listeners exactly once (C4.3)', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _named('Alpha'));
    int notifications = 0;
    c.addListener(() => notifications++);
    c.rename('Beta');
    expect(notifications, 1);
    c.dispose();
  });

  test('rename to the current name is a no-op — no history, no notify (C4.4)',
      () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _named('Alpha'));
    int notifications = 0;
    c.addListener(() => notifications++);
    c.rename('Alpha');
    expect(notifications, 0);
    expect(c.canUndo, isFalse);
    c.dispose();
  });

  test('an empty or whitespace-only name is stored verbatim as empty (FR-010)',
      () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _named('Alpha'));
    c.rename('   ');
    expect(c.definition.name.trim(), isEmpty);
    c.dispose();
  });

  test('a renamed definition round-trips losslessly through the codec (C4.5)',
      () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _named('Alpha'));
    c.rename('Renamed report');

    final String json = JetReportFormat.encodeDefinitionJson(c.definition);
    final ReportDefinition reopened =
        JetReportFormat.decodeDefinitionJson(json);
    expect(reopened.name, 'Renamed report');
    // encode→decode→encode is a fixed point: no field, schema, or value drift.
    expect(
      JetReportFormat.encodeDefinition(reopened),
      equals(JetReportFormat.encodeDefinition(c.definition)),
    );
    c.dispose();
  });
}
