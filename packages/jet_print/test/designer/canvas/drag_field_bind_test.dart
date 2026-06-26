// Drag-a-field-to-bind (US2 / FR-011).
//
// Leaf fields in the Data Source panel are draggable; a collection (branch)
// node is not. Dropping a field on a band creates a text element bound to
// `$F{field}`. Public API only — `FieldDragData` is internal, so draggability is
// asserted via a widget predicate scoped to the right panel, and the drop is
// verified through the controller's model.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

// Every band across a (reified) definition: furniture slots, body once-bands,
// and the recursive scope tree (per-row bands + group header/footer bands).
Iterable<Band> _allBands(ReportDefinition def) sync* {
  final PageFurniture f = def.furniture;
  for (final Band? b in <Band?>[
    f.pageHeader,
    f.pageFooter,
    f.columnHeader,
    f.columnFooter,
    f.background,
    def.body.title,
    def.body.summary,
    def.body.noData,
  ]) {
    if (b != null) yield b;
  }
  yield* _scopeBands(def.body.root);
}

Iterable<Band> _scopeBands(DetailScope scope) sync* {
  for (final GroupLevel g in scope.groups) {
    if (g.header != null) yield g.header!;
    if (g.footer != null) yield g.footer!;
  }
  for (final ScopeNode node in scope.children) {
    switch (node) {
      case BandNode(:final Band band):
        yield band;
      case NestedScope(:final DetailScope scope):
        yield* _scopeBands(scope);
    }
  }
}

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('total', type: JetFieldType.double),
    FieldDef(
      'lines',
      type: JetFieldType.collection,
      fields: <FieldDef>[FieldDef('description', type: JetFieldType.string)],
    ),
  ],
);

void main() {
  testWidgets(
      'leaf fields are draggable; collection branches and '
      'collapsed children are not', (
    WidgetTester tester,
  ) async {
    await pumpDesignerWith(tester, dataSchema: _invoice);

    // Two top-level scalar fields (`invoiceNo`, `total`) are draggable as leaf
    // rows. The `lines` collection branch is NOT draggable (its row drives
    // expand/collapse; lists are created via its `＋` action). `description`
    // sits inside the collapsed branch so it is not rendered. Total = 2.
    final Finder panelDraggables = find.descendant(
      of: find.byKey(kRightPanelKey),
      matching: find.byWidgetPredicate((Widget w) => w is Draggable),
    );
    expect(panelDraggables, findsNWidgets(2));
    expect(find.text('lines'), findsOneWidget);
  });

  testWidgets('dropping a field on the canvas creates a bound text element', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);

    // Drag `invoiceNo` from the panel onto a band near the top of the page.
    final Offset source = tester.getCenter(find.text('invoiceNo'));
    final Offset target =
        tester.getTopLeft(find.byKey(kDesignPageKey)) + const Offset(120, 28);
    await tester.drag(find.text('invoiceNo'), target - source);
    await tester.pumpAndSettle();

    final Iterable<TextElement> bound = _allBands(c.definition)
        .expand((Band b) => b.elements)
        .whereType<TextElement>()
        .where((TextElement e) => e.expression == r'$F{invoiceNo}');
    expect(bound, isNotEmpty,
        reason: 'a field dropped on a band should create a bound text element');
  });
}
