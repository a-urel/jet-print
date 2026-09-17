// performance guard: a multi-element drag over a large design stays LINEAR.
//
// Drags 20 selected elements across twelve frames, first over a 200-element
// design and then over a 400-element one, and asserts on how much *model
// traversal* each drag performs — not on how long it took.
//
// Why not a stopwatch: a wall-clock ceiling measures the machine, not the code.
// The previous version of this test asserted `elapsed < 2000ms`; on unmodified
// code it failed at 3590ms under eight competing CPU hogs, and once in an
// ordinary full-suite run. Any unrelated change that adds concurrent test
// processes could push it over, so it reported load as a regression.
//
// What is counted instead: every read of `ReportElement.id`. That is the
// comparison the designer's element lookups actually perform —
// `JetReportDesignerController._locate` resolves each selected id by scanning
// the owning band's elements, and the design-time layout and frame builder key
// their per-element work off the same field. So the count *is* the work, not a
// proxy for it: index the lookup and it falls, scan more and it rises.
//
// The assertion is a RATIO, not an absolute. Doubling the design size doubles
// linear per-frame work, so a healthy engine lands near 2.0x. Per-frame work
// that is quadratic in the design size (re-walking every element once per
// selected element, re-laying-out per element, a per-element rect lookup that
// scans) lands near 4.0x. The ceiling sits between them. An absolute count
// would be brittle — any legitimate extra walk moves it — while the ratio locks
// the shape of the curve, which is the actual claim.
//
// Measured when this guard was written: 50,302 and 90,102 traversals — a 1.79x
// ratio (part of the per-frame cost is selection-sized, so healthy sits a little
// under 2.0x). The counts are byte-identical run to run, and stay identical
// under eight competing CPU hogs that stretch the run from 3s to 18s. Reverting
// one of the layout's O(1) element lookups to an O(n) scan takes the ratio to
// 3.97x and fails this test.
//
// What this guard does NOT see: a regression that walks some other per-element
// structure — a rect map, a widget list — without touching the elements
// themselves. It watches element traversal, which is where this designer's
// lookups actually live, not every conceivable way to spend a frame.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

/// Elements per row when seeding, and the band height that fits the tallest
/// seeded grid. Both are constant across sizes so the two runs differ only in
/// element count.
const int _perRow = 20;
const double _bandHeight = 240;

/// The two design sizes. The larger is exactly twice the smaller, so linear
/// per-frame work predicts a 2.0x traversal ratio.
const int _smallDesign = 200;
const int _largeDesign = 400;

/// How many elements are dragged at once, and for how many frames.
const int _selected = 20;
const int _frames = 12;

/// The ratio ceiling: comfortably above linear (2.0x), far below quadratic
/// (4.0x). Traversal counts are deterministic, so this margin absorbs engine
/// changes, not machine noise.
const double _maxScaling = 2.6;

void main() {
  testWidgets('a 20-element drag scales linearly with design size',
      (WidgetTester tester) async {
    final int small = await _dragTraversals(tester, _smallDesign);
    final int large = await _dragTraversals(tester, _largeDesign);

    expect(small, greaterThan(0),
        reason: 'the drag must actually traverse the model; a zero count means '
            'the counting elements never reached the designer');
    final double scaling = large / small;
    expect(scaling, lessThan(_maxScaling),
        reason: 'doubling the design size must at most double the per-frame '
            'traversal ($small -> $large is ${scaling.toStringAsFixed(2)}x); '
            'a ratio near 4x signals O(n^2)-per-frame work');
  });
}

/// Pumps a designer over a [count]-element design, drags [_selected] of them
/// across [_frames] frames, and returns how many element-id comparisons that
/// drag performed.
Future<int> _dragTraversals(WidgetTester tester, int count) async {
  final JetReportDesignerController c = JetReportDesignerController();
  c.open(_seeded(c.definition, count));
  await pumpDesignerWith(tester, controller: c);

  final List<String> ids = c.definition.body.root.children
      .whereType<BandNode>()
      .expand((BandNode n) => n.band.elements)
      .map((ReportElement e) => e.id)
      .toList();
  expect(ids, hasLength(count),
      reason: 'the seeded design must carry exactly $count elements');
  c.selectElements(ids.take(_selected));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull,
      reason: 'a $count-element design must build without error');
  final double startX = _elementX(c, ids.first);

  // Count only the drag itself: seeding, the first layout and the initial
  // record are one-off costs that no per-frame budget should be charged for.
  _CountingText.idReads = 0;
  c.beginMove();
  for (int frame = 1; frame <= _frames; frame++) {
    c.updateMove(JetOffset(frame * 2.0, frame.toDouble()));
    await tester.pump(const Duration(milliseconds: 16));
  }
  c.commitMove();
  await tester.pumpAndSettle();
  final int traversals = _CountingText.idReads;

  expect(tester.takeException(), isNull,
      reason: 'the multi-element drag must not throw');
  // The selection actually moved (the drag was real, not a no-op).
  expect(_elementX(c, ids.first), greaterThan(startX));
  return traversals;
}

/// Returns [definition] with the first per-row band's elements replaced by
/// [count] counting text elements laid out in a grid that fits the band.
ReportDefinition _seeded(ReportDefinition definition, int count) {
  final DetailScope root = definition.body.root;
  final List<ScopeNode> children = <ScopeNode>[];
  bool seeded = false;
  for (final ScopeNode node in root.children) {
    if (!seeded && node is BandNode) {
      children.add(BandNode(
          node.band.copyWith(height: _bandHeight, elements: _elements(count))));
      seeded = true;
    } else {
      children.add(node);
    }
  }
  expect(seeded, isTrue,
      reason: 'the default design must expose a per-row band to seed');
  return definition.copyWith(
      body: definition.body.copyWith(root: root.copyWith(children: children)));
}

List<ReportElement> _elements(int count) => <ReportElement>[
      for (int i = 0; i < count; i++)
        _CountingText(
          id: 'perf$i',
          bounds: JetRect(
            x: (i % _perRow) * 14.0 + 4,
            y: (i ~/ _perRow) * 9.0 + 4,
            width: 12,
            height: 8,
          ),
          text: 'x',
        ),
    ];

double _elementX(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds
        .x;

/// A text element that tallies every read of its [id].
///
/// `typeKey` stays `'text'`, so the unchanged text renderer draws it and the
/// design-time path is the production one — the only difference is that the
/// element can say how often it was looked at.
class _CountingText extends TextElement {
  const _CountingText({
    required super.id,
    required super.bounds,
    required super.text,
  });

  /// Element-id comparisons since the last reset. Static because the count is
  /// about the *design*, not about one element.
  static int idReads = 0;

  @override
  String get id {
    idReads++;
    return super.id;
  }

  /// `withBounds` must return the same concrete type — the move command rebuilds
  /// every dragged element through it, and a plain [TextElement] here would stop
  /// counting exactly the 20 elements the drag touches most.
  ///
  /// Reads `super.id` rather than [id] so this bookkeeping does not inflate the
  /// count it exists to keep honest.
  @override
  _CountingText withBounds(JetRect bounds) =>
      _CountingText(id: super.id, bounds: bounds, text: text);
}
