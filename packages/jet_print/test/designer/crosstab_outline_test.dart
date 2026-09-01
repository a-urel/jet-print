// Widget test: a crosstab's Outline row. Spec A shipped it read-only; spec B
// makes it a real authoring row — selectable, renameable, reorderable and
// removable — and adds the root scope's "Add crosstab" menu entry.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

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
