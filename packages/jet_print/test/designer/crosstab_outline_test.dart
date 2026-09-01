// Widget test: a crosstab's Outline row. Spec A shipped it read-only; spec B
// makes it a real authoring row — selectable, renameable, reorderable and
// removable — and adds the root scope's "Add crosstab" menu entry.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

Finder _inPanel(String text) =>
    find.descendant(of: find.byKey(kRightPanelKey), matching: find.text(text));

/// A one-row-group x one-column-group crosstab, id `ct1` (matching the canvas
/// placeholder key under test), as the sole child of an otherwise-blank body.
ReportDefinition _defWithCrosstab({String? name = 'Sales pivot'}) =>
    ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            CrosstabNode(Crosstab(
              id: 'ct1',
              name: name,
              rowGroups: const <CrosstabGroup>[
                CrosstabGroup(
                  id: 'g-region',
                  name: 'Region',
                  expression: r'$F{region}',
                ),
              ],
              columnGroups: const <CrosstabGroup>[
                CrosstabGroup(
                    id: 'g-year', name: 'Year', expression: r'$F{year}'),
              ],
              measures: const <CrosstabMeasure>[
                CrosstabMeasure(
                  id: 'm-amount',
                  name: 'Amount',
                  expression: r'$F{amount}',
                  aggregate: JetCalculation.sum,
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// Pumps the designer over a definition holding [_defWithCrosstab]([name]),
/// mirroring the other outline tests' `pumpDesigner`/harness pattern rather
/// than hand-rolling the `ShadApp`/localization wiring here.
Future<JetReportDesignerController> _designerWith(
  WidgetTester tester, {
  String? name = 'Sales pivot',
}) async {
  final JetReportDesignerController controller =
      JetReportDesignerController(definition: _defWithCrosstab(name: name));
  addTearDown(controller.dispose);
  await pumpDesigner(tester,
      designer: JetReportDesigner(controller: controller));
  return controller;
}

Future<void> _openOutline(WidgetTester tester) async {
  await tester.tap(find.text('Outline').first);
  await tester.pumpAndSettle();
}

const ValueKey<String> _rowKey =
    ValueKey<String>('jet_print.designer.outline.crosstab.ct1');

void main() {
  testWidgets('a crosstab appears as an outline row',
      (WidgetTester tester) async {
    await _designerWith(tester);
    await _openOutline(tester);
    expect(_inPanel('Sales pivot'), findsOneWidget);
  });

  testWidgets('a nameless crosstab falls back to the localized label',
      (WidgetTester tester) async {
    await _designerWith(tester, name: null);
    await _openOutline(tester);
    expect(_inPanel('Crosstab'), findsOneWidget);
  });

  testWidgets('the canvas reserves a block for the crosstab',
      (WidgetTester tester) async {
    await _designerWith(tester);
    expect(find.byKey(const ValueKey<String>('crosstab-placeholder-ct1')),
        findsOneWidget);
  });

  testWidgets('tapping the row selects the crosstab',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _designerWith(tester);
    await _openOutline(tester);
    await tester.tap(find.byKey(_rowKey));
    await tester.pumpAndSettle();
    expect(c.selection.crosstabId, 'ct1');
  });

  testWidgets('the remove action deletes it', (WidgetTester tester) async {
    final JetReportDesignerController c = await _designerWith(tester);
    await _openOutline(tester);
    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.outline.crosstab.ct1.remove')));
    await tester.pumpAndSettle();
    expect(c.definition.body.root.children.whereType<CrosstabNode>(), isEmpty);
    expect(find.byKey(_rowKey), findsNothing);
  });

  // The stale-inline-editor guard in outline_panel's build discards _editingId
  // whenever the edited object is not in the selection. It knew about band and
  // element selections only, so a crosstab's editor was torn down on the very
  // next build and the rename field never appeared.
  testWidgets('double-tapping the row opens an editor that commits a rename',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _designerWith(tester);
    await _openOutline(tester);
    final Offset centre = tester.getCenter(find.byKey(_rowKey));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(centre);
    await tester.pumpAndSettle();

    final Finder field = find.descendant(
        of: find.byKey(_rowKey), matching: find.byType(EditableText));
    expect(field, findsOneWidget,
        reason: 'the inline rename editor must survive the next build');

    await tester.enterText(field, 'Bölge pivotu');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
        c.definition.body.root.children
            .whereType<CrosstabNode>()
            .single
            .crosstab
            .name,
        'Bölge pivotu');
  });

  testWidgets('the move actions are offered', (WidgetTester tester) async {
    await _designerWith(tester);
    await _openOutline(tester);
    for (final String suffix in <String>['up', 'down']) {
      expect(
          find.byKey(ValueKey<String>(
              'jet_print.designer.outline.crosstab.ct1.$suffix')),
          findsOneWidget);
    }
  });

  // "Enabled when the source has at least one SCALAR field" — a collection whose
  // children are all themselves collections can be bucketed by nothing, so its
  // submenu entry must be disabled rather than silently no-opping in
  // createCrosstab.
  testWidgets('a collection with no scalar child is offered but disabled',
      (WidgetTester tester) async {
    final JetReportDesignerController c = JetReportDesignerController(
      definition: const ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        body: ReportBody(root: DetailScope(id: 'root')),
      ),
    );
    addTearDown(c.dispose);
    await pumpDesigner(
      tester,
      designer: JetReportDesigner(
        controller: c,
        dataSchema: const JetDataSchema(
          name: 'S',
          fields: <FieldDef>[
            FieldDef('region', type: JetFieldType.string),
            // Only collection children — nothing to bucket by.
            FieldDef('boxes', type: JetFieldType.collection, fields: <FieldDef>[
              FieldDef('items', type: JetFieldType.collection),
            ]),
          ],
        ),
      ),
    );
    await _openOutline(tester);
    await tester.tap(find.byKey(
        const ValueKey<String>('jet_print.designer.outline.scope.root.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.outline.scope.root.add.crosstab')));
    await tester.pumpAndSettle();
    // Asserted on the option's own enabled flag, not merely on "nothing
    // happened": createCrosstab already refuses a scalar-less source, so a
    // tap-and-check would pass with a live-looking, dead menu item.
    final ShadContextMenuItem boxes = tester.widget<ShadContextMenuItem>(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.root.add.crosstab.field.boxes')));
    expect(boxes.enabled, isFalse);
    final ShadContextMenuItem rows = tester.widget<ShadContextMenuItem>(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.root.add.crosstab.rows')));
    expect(rows.enabled, isTrue, reason: 'the scope itself has a scalar');
  });

  // A crosstab is root-scope only (spec A decision 8) — validate() rejects one
  // in a nested scope, so the affordance must not offer it there.
  testWidgets('Add crosstab is offered on the root scope only',
      (WidgetTester tester) async {
    final JetReportDesignerController c = JetReportDesignerController(
      definition: const ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[
                  BandNode(Band(id: 'row', type: BandType.detail, height: 12)),
                ],
              )),
            ],
          ),
        ),
      ),
    );
    addTearDown(c.dispose);
    await pumpDesigner(tester, designer: JetReportDesigner(controller: c));
    await _openOutline(tester);

    await tester.tap(find.byKey(
        const ValueKey<String>('jet_print.designer.outline.scope.root.add')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.root.add.crosstab')),
        findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const ValueKey<String>('jet_print.designer.outline.scope.lines.add')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.lines.add.crosstab')),
        findsNothing);
  });
}
