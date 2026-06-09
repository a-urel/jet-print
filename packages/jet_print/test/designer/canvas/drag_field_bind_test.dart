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
  testWidgets('only leaf fields are draggable (collection nodes are not)', (
    WidgetTester tester,
  ) async {
    await pumpDesignerWith(tester, dataSchema: _invoice);

    // The two top-level scalar fields are draggable; `lines` (collection) is a
    // branch and not wrapped in a Draggable. (description is collapsed.)
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

    final Iterable<TextElement> bound = c.template.bands
        .expand((ReportBand b) => b.elements)
        .whereType<TextElement>()
        .where((TextElement e) => e.expression == r'$F{invoiceNo}');
    expect(bound, isNotEmpty,
        reason: 'a field dropped on a band should create a bound text element');
  });
}
