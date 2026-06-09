// Bulk operations through the controller (US4 / T054 / FR-012/013/014/015/016).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportTemplate _fixture() => const ReportTemplate(
      name: 'F',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
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
            TextElement(
                id: 'c',
                bounds: JetRect(x: 90, y: 80, width: 20, height: 10),
                text: 'c'),
          ],
        ),
      ],
    );

List<ReportElement> _els(JetReportDesignerController c) =>
    c.template.bands.first.elements;

JetRect _boundsOf(JetReportDesignerController c, String id) =>
    _els(c).firstWhere((ReportElement e) => e.id == id).bounds;

JetReportDesignerController _open() =>
    JetReportDesignerController()..open(_fixture());

void main() {
  test('delete removes the selection and is undoable', () {
    final JetReportDesignerController c = _open()
      ..select('a')
      ..addToSelection('b');
    c.delete();
    expect(_els(c).map((ReportElement e) => e.id), <String>['c']);
    expect(c.selection.isEmpty, isTrue);
    c.undo();
    expect(_els(c).length, 3);
    c.dispose();
  });

  test('selectAll then delete clears every element', () {
    final JetReportDesignerController c = _open()..selectAll();
    expect(c.selection.length, 3);
    c.delete();
    expect(_els(c), isEmpty);
    c.dispose();
  });

  test('toggleSelection adds then removes', () {
    final JetReportDesignerController c = _open()..select('a');
    c.toggleSelection('b');
    expect(c.selection.length, 2);
    c.toggleSelection('b');
    expect(c.selection.length, 1);
    c.dispose();
  });

  test('bringToFront moves the selected element to the end of paint order', () {
    final JetReportDesignerController c = _open()..select('a');
    c.bringToFront();
    expect(_els(c).map((ReportElement e) => e.id), <String>['b', 'c', 'a']);
    c.sendToBack();
    expect(_els(c).map((ReportElement e) => e.id), <String>['a', 'b', 'c']);
    c.dispose();
  });

  test('copy + paste inserts an offset copy with a fresh id, selected', () {
    final JetReportDesignerController c = _open()..select('a');
    c.copy();
    c.paste();
    expect(_els(c).length, 4);
    final String newId = c.selection.singleOrNull!;
    expect(newId, isNot('a'));
    final JetRect b = _boundsOf(c, newId);
    expect(b.x, 18); // 10 + 8 offset
    expect(b.y, 18);
    c.dispose();
  });

  test('duplicate copies the selection in place without using the clipboard',
      () {
    final JetReportDesignerController c = _open()..select('b');
    c.duplicate();
    expect(_els(c).length, 4);
    expect(_boundsOf(c, c.selection.singleOrNull!).x, 53); // 45 + 8
    c.dispose();
  });

  test('cut removes the selection but keeps it for paste', () {
    final JetReportDesignerController c = _open()..select('a');
    c.cut();
    expect(_els(c).length, 2);
    c.paste();
    expect(_els(c).length, 3); // the cut element is pasted back
    c.dispose();
  });

  test('align left moves every selected element to the leftmost x', () {
    final JetReportDesignerController c = _open()..selectAll();
    c.align(AlignKind.left);
    expect(_boundsOf(c, 'a').x, 10);
    expect(_boundsOf(c, 'b').x, 10);
    expect(_boundsOf(c, 'c').x, 10);
    expect(c.canUndo, isTrue);
    c.dispose();
  });

  test('align top moves every selected element to the topmost y', () {
    final JetReportDesignerController c = _open()..selectAll();
    c.align(AlignKind.top);
    expect(_boundsOf(c, 'a').y, 10);
    expect(_boundsOf(c, 'b').y, 10);
    expect(_boundsOf(c, 'c').y, 10);
    c.dispose();
  });

  test('distribute horizontal evenly spaces the middle element by center', () {
    // centers: a=20, b=55, c=100 → b should move to center 60 (x = 50).
    final JetReportDesignerController c = _open()..selectAll();
    c.distribute(DistributeAxis.horizontal);
    expect(_boundsOf(c, 'b').x, 50);
    // Endpoints stay put.
    expect(_boundsOf(c, 'a').x, 10);
    expect(_boundsOf(c, 'c').x, 90);
    c.dispose();
  });

  test(
      'nudge moves the selection by exact points (no snapping) and is undoable',
      () {
    final JetReportDesignerController c = _open()..select('a');
    c.nudge(1, 0);
    expect(_boundsOf(c, 'a').x, 11);
    c.nudge(0, -1);
    expect(_boundsOf(c, 'a').y, 9);
    c.undo();
    c.undo();
    expect(
        _boundsOf(c, 'a'), const JetRect(x: 10, y: 10, width: 20, height: 10));
    c.dispose();
  });
}
