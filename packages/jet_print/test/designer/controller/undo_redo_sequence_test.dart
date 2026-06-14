// Undo/redo at scale (US3 / T049 / contracts §7.5 / SC-003): a ≥50-step edit
// sequence undoes in reverse and redoes in order, with model size and selection
// exact at every step; a new edit after undo discards redo; past-the-end is a
// no-op.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

int _count(JetReportDesignerController c) => c.definition.body.root.children
    .whereType<BandNode>()
    .fold<int>(0, (int n, BandNode b) => n + b.band.elements.length);

void main() {
  test('a 60-step create sequence fully undoes and redoes with exact state',
      () {
    final JetReportDesignerController c = JetReportDesignerController();
    const int steps = 60;
    const List<DesignerToolType> cycle = DesignerToolType.values;

    // Snapshot (count, selectedId) after each edit; index 0 is the origin.
    final List<({int count, String? sel})> states =
        <({int count, String? sel})>[
      (count: _count(c), sel: c.selection.singleOrNull),
    ];
    for (int i = 0; i < steps; i++) {
      c.createElement(cycle[i % cycle.length],
          bandId: 'detail', at: const JetOffset(10, 10));
      states.add((count: _count(c), sel: c.selection.singleOrNull));
    }
    expect(_count(c), steps);

    // Undo all the way to the origin, checking exact state in reverse.
    for (int i = steps; i > 0; i--) {
      expect(_count(c), states[i].count);
      expect(c.selection.singleOrNull, states[i].sel);
      expect(c.canUndo, isTrue);
      c.undo();
    }
    expect(_count(c), 0);
    expect(c.selection.isEmpty, isTrue);
    expect(c.canUndo, isFalse);

    // Redo all the way forward, checking exact state in order.
    for (int i = 1; i <= steps; i++) {
      expect(c.canRedo, isTrue);
      c.redo();
      expect(_count(c), states[i].count);
      expect(c.selection.singleOrNull, states[i].sel);
    }
    expect(c.canRedo, isFalse);
    c.dispose();
  });

  test('a new edit after undo discards the redo stack', () {
    final JetReportDesignerController c = JetReportDesignerController();
    for (int i = 0; i < 5; i++) {
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(10, 10));
    }
    c.undo();
    c.undo();
    expect(c.canRedo, isTrue);
    c.createElement(DesignerToolType.shape,
        bandId: 'detail', at: const JetOffset(10, 10));
    expect(c.canRedo, isFalse);
    c.dispose();
  });

  test('undo/redo past the ends are no-ops', () {
    final JetReportDesignerController c = JetReportDesignerController();
    expect(c.canUndo, isFalse);
    c.undo();
    c.redo();
    expect(_count(c), 0);
    c.dispose();
  });
}
