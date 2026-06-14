// Controller-core unit test (Phase 2 / T007 / contracts §7.5 / SC-003).
//
// Under test/designer/, so it stands in for an external consumer: it imports
// ONLY the public entry point. This proves the controller's id-assignment and
// undo/redo contract through the surfaced API alone.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _seeded() => const ReportDefinition(
      name: 'Seeded',
      page: PageFormat.a4Portrait,
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
                  id: 'text3',
                  bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
                  text: 'a',
                ),
                TextElement(
                  id: 'text7',
                  bounds: JetRect(x: 0, y: 20, width: 10, height: 10),
                  text: 'b',
                ),
              ],
            )),
          ],
        ),
      ),
    );

int _detailCount(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .first
        .band
        .elements
        .length;

void main() {
  test('a fresh no-arg controller has a default definition, empty history', () {
    final JetReportDesignerController c = JetReportDesignerController();
    expect(c.definition.body.root.children,
        isNotEmpty); // default blank band structure
    expect(c.canUndo, isFalse);
    expect(c.canRedo, isFalse);
    expect(c.selection.isEmpty, isTrue);
    c.dispose();
  });

  test('open seeds the id sequence past the largest numeric suffix', () {
    final JetReportDesignerController c = JetReportDesignerController()
      ..open(_seeded()); // existing ids text3, text7 -> next is 8
    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(5, 5));
    expect(c.selection.singleOrNull, 'text8');
    c.dispose();
  });

  test('undo/redo restore BOTH definition and selection', () {
    final JetReportDesignerController c = JetReportDesignerController()
      ..open(_seeded());
    expect(_detailCount(c), 2);

    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(5, 5));
    expect(_detailCount(c), 3);
    expect(c.selection.singleOrNull, 'text8');
    expect(c.canUndo, isTrue);

    c.undo();
    expect(_detailCount(c), 2);
    expect(
        c.selection.isEmpty, isTrue); // selection before the create was empty
    expect(c.canRedo, isTrue);

    c.redo();
    expect(_detailCount(c), 3);
    expect(c.selection.singleOrNull, 'text8'); // selection restored exactly
    c.dispose();
  });

  test('a new edit after undo discards the redo stack', () {
    final JetReportDesignerController c = JetReportDesignerController()
      ..open(_seeded());
    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(5, 5));
    c.undo();
    expect(c.canRedo, isTrue);
    c.createElement(DesignerToolType.shape,
        bandId: 'detail', at: const JetOffset(5, 5));
    expect(c.canRedo, isFalse);
    c.dispose();
  });

  test('undo/redo past the ends is a no-op', () {
    final JetReportDesignerController c = JetReportDesignerController()
      ..open(_seeded());
    expect(c.canUndo, isFalse);
    c.undo();
    expect(_detailCount(c), 2);
    c.redo();
    expect(_detailCount(c), 2);
    c.dispose();
  });

  test('notifies listeners on every state change', () {
    final JetReportDesignerController c = JetReportDesignerController()
      ..open(_seeded());
    int notifications = 0;
    c.addListener(() => notifications++);
    c.createElement(DesignerToolType.text,
        bandId: 'detail', at: const JetOffset(5, 5));
    c.undo();
    c.redo();
    c.select('text3');
    expect(notifications, greaterThanOrEqualTo(4));
    c.dispose();
  });
}
