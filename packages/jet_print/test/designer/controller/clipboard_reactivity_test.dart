// Controller clipboard reactivity (016 / C1 / FR-004/005/007/009).
//
// The two UI surfaces (toolbar group + canvas context menu) both bind their
// enablement to `canCopy` / `canPaste` and rebuild through DesignerScope's
// InheritedNotifier — so this pins, at the controller seam:
//   * copy() notifies exactly once (so Paste re-enables after a mouse Copy) but
//     creates NO undo entry (Copy is not undoable, FR-009);
//   * canCopy / canPaste track the data-model truth table; and
//   * after cut() the selection is empty (canCopy false) while the clipboard
//     holds the cut element (canPaste true) — the "selection lost after Cut" edge.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _fixture() => const ReportDefinition(
      name: 'F',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 300,
              elements: <ReportElement>[
                TextElement(
                    id: 'a',
                    bounds: JetRect(x: 10, y: 10, width: 20, height: 10),
                    text: 'a'),
                TextElement(
                    id: 'b',
                    bounds: JetRect(x: 45, y: 40, width: 20, height: 10),
                    text: 'b'),
              ],
            )),
          ],
        ),
      ),
    );

JetReportDesignerController _open() =>
    JetReportDesignerController()..open(_fixture());

void main() {
  test('copy() notifies exactly once and creates no undo entry', () {
    final JetReportDesignerController c = _open()..select('a');
    int notifications = 0;
    c.addListener(() => notifications++);

    expect(c.canUndo, isFalse, reason: 'fresh document has no history');
    c.copy();

    expect(notifications, 1,
        reason: 'a mouse Copy must notify so Paste re-enables (D1)');
    expect(c.canUndo, isFalse,
        reason: 'Copy is not undoable — it must not push a history entry');
    c.dispose();
  });

  test('canCopy / canPaste track the truth table: empty → select → copy → cut',
      () {
    final JetReportDesignerController c = _open();

    // Empty selection, empty clipboard.
    expect(c.canCopy, isFalse);
    expect(c.canPaste, isFalse);

    // Selecting an element enables Cut/Copy; clipboard still empty.
    c.select('a');
    expect(c.canCopy, isTrue);
    expect(c.canPaste, isFalse);

    // A Copy fills the clipboard → Paste enabled; selection intact → Copy stays.
    c.copy();
    expect(c.canCopy, isTrue);
    expect(c.canPaste, isTrue);

    c.dispose();
  });

  test('after cut() the selection is empty but the clipboard holds the element',
      () {
    final JetReportDesignerController c = _open()..select('a');

    c.cut();

    // Edge case "Selection lost after Cut": cut copies then deletes, emptying
    // the selection (canCopy false) while the clipboard retains it (canPaste).
    expect(c.canCopy, isFalse, reason: 'cut empties the selection');
    expect(c.canPaste, isTrue, reason: 'the cut element is on the clipboard');
    c.dispose();
  });
}
